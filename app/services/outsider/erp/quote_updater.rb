# OUTSIDER: grava no ERP a edição de um orçamento que já estava gravado (Outsider::Erp::QuoteRevision abriu a edição).
# As mesmas peças do Outsider::Erp::QuoteCreator, na ordem: confere a trava do ERP -> tira as linhas do orçamento ->
# grava as linhas de novo pelas funções do ERP -> finaliza -> Demais Condições, A/C, observação e vendedor. O número do
# orçamento não muda. A trava (NEGOCIAÇÃO e ninguém com ele aberto no Mais Prático) vai no WHERE de cada escrita fora das
# funções, então ela vale mesmo se o orçamento for aberto no desktop no meio do caminho.
# Se o ERP cair no meio, o orçamento lá fica sem parte das linhas: a edição volta para a tela com o aviso e "Salvar no
# ERP" de novo refaz tudo (tira e grava outra vez).
class Outsider::Erp::QuoteUpdater < Outsider::Erp::QuoteCreator
  def call
    ensure_revision!
    with_lock do
      number = @budget.erp_number
      customer = customer!
      plan = plan_lines
      ensure_unlocked!(number)
      @client.query_execute(revision_builder(customer, plan).clear_sql(number))
      raise Invalid, 'em_uso' if current_codes(number).any?

      plan.reject { |line| line[:kind] == :skip }.each { |line| insert_revision_line(number, line) }
      @client.query_execute(revision_builder(customer, plan).finalize_sql(number))
      write_revision_conditions(number, customer, plan)
      finish_revision(number, plan)
    end
  end

  private

  def ensure_revision!
    raise Disabled unless @settings.quote_write_enabled?
    raise Invalid, 'not_revising' unless @budget.revision && @budget.erp_number.present?
    raise Invalid, 'empresa' unless @settings.companies.include?(@budget.company)
    raise Invalid, 'sem_itens' if @budget.items.empty?
    raise Invalid, 'desconto_sem_liberacao' if Outsider::Erp::DiscountPolicy.new(@budget, @settings).blocked?
  end

  def revision_builder(customer, plan)
    Outsider::Erp::QuoteBuilder.new(@budget, document: customer['documento'], seller: @budget.terms['vendedor'],
                                             service_codes: plan.select { |line| line[:kind] == :service }.map { |line| line[:item]['codigo'].to_i },
                                             revision: { columns: quote_columns })
  end

  def quote_columns
    @quote_columns ||= Outsider::Erp::Schema.new(@budget.account, client: @client).columns(@budget.company, 'orcamento')
  end

  # o status mudou ou alguém abriu no Mais Prático depois que a edição foi aberta: não mexe em nada
  def ensure_unlocked!(number)
    sql = Outsider::Erp::QuoteBuilder.new(@budget, document: nil, seller: nil, revision: { columns: quote_columns }).editable_sql(number)
    raise Invalid, 'em_uso' if @client.query_execute(sql).grep(Hash).empty?
  end

  def insert_revision_line(number, line)
    sql_builder = Outsider::Erp::QuoteBuilder.new(@budget, document: nil, seller: nil, revision: { columns: quote_columns })
    sql = line[:kind] == :service ? sql_builder.service_sql(number, line[:item]) : sql_builder.item_sql(number, line[:item])
    @client.query_execute(sql)
  end

  def write_revision_conditions(number, customer, plan)
    sql = revision_builder(customer, plan).conditions_sql(number, quote_columns)
    @client.query_execute(sql) if sql
  rescue Outsider::Erp::Client::Error => e
    @conditions_error = e.message
  end

  # volta ao status de antes (gravado pelo chat ou feito no Mais Prático) e guarda quem editou e quando
  def finish_revision(number, plan)
    skipped = plan.select { |line| line[:kind] == :skip }.map { |line| label(line, line[:reason]) } +
              lost_lines(number, plan).map { |line| label(line, 'ncm') }
    result = @budget.erp_result.except('revision', 'error', 'progress')
    save(status: @budget.revision['from'] == 'imported' ? :imported : :created,
         erp_result: result.merge('skipped' => skipped, 'conditions_error' => @conditions_error, 'edits' => edits(result)).compact)
    log("edição gravada #{@budget.company}/#{number}, #{skipped.size} fora")
    @budget
  end

  # as últimas 20 edições (quem, quando, quantos itens)
  def edits(result)
    Array(result['edits']).last(19) + [{ 'at' => Time.current.iso8601, 'user_id' => @user&.id, 'name' => @user&.name, 'items' => @budget.items.size }]
  end
end
