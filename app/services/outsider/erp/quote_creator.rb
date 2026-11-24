# OUTSIDER: grava no ERP um orçamento de peças e serviços feito no chat (Outsider::Erp::Budget). Orquestra (não monta SQL
# nem fala HTTP direto): confere o cliente e os produtos na unidade, pede as chamadas ao Outsider::Erp::QuoteBuilder e
# roda pelo Client#query_execute na ordem cabeçalho -> linhas -> finaliza -> Demais Condições -> conferência.
#
# Gates: gravação de orçamento ligada nas Configurações (desligada por padrão), forma de pagamento e vendedor definidos,
# desconto acima do limite liberado (Outsider::Erp::DiscountPolicy).
# Retomável: o número do ERP fica salvo logo depois do cabeçalho e o avanço a cada linha; se o ERP cair no meio, rodar de
# novo continua de onde parou (o cabeçalho é idempotente e linha que já entrou não entra de novo). Uma gravação por vez
# por orçamento (trava no Redis).
class Outsider::Erp::QuoteCreator
  class Disabled < StandardError; end
  class Invalid < StandardError; end

  LOCK_SECONDS = 180

  def initialize(budget, user:)
    @budget = budget
    @user = user
    @settings = Outsider::Erp::Settings.new(budget.account)
    @client = Outsider::Erp::Client.new(@settings)
    @catalog = Outsider::Erp::Catalog.new(budget.account)
  end

  def call
    ensure_ready!
    return @budget if @budget.created?

    with_lock do
      customer = customer!
      plan = plan_lines
      number = @budget.erp_number || create_header(customer, plan)
      insert_lines(number, plan)
      insert_lost_parts(number, plan, Outsider::Erp::QuoteBuilder.new(@budget, document: nil, seller: nil))
      @client.query_execute(builder(customer, plan).finalize_sql(number))
      write_conditions(number, customer, plan)
      finish(number, plan)
    end
  end

  private

  def ensure_ready!
    raise Disabled unless @settings.quote_write_enabled?
    raise Invalid, 'forma_pagto' unless @budget.terms['forma_pagto'].to_i.positive?
    raise Invalid, 'vendedor' unless @budget.terms['vendedor'].to_i.positive?
    raise Invalid, 'sem_cliente' unless @budget.customer_code.to_i.positive?
    raise Invalid, 'empresa' unless @settings.companies.include?(@budget.company)
    raise Invalid, 'sem_itens' if @budget.items.empty?

    ensure_discount!
  end

  # desconto acima do limite precisa estar liberado (gravação que parou no meio já passou por aqui)
  def ensure_discount!
    return if @budget.erp_number.present?

    raise Invalid, 'desconto_sem_liberacao' if Outsider::Erp::DiscountPolicy.new(@budget, @settings).blocked?
  end

  def with_lock
    key = "outsider_erp:#{@budget.account_id}:budget_lock:#{@budget.id}"
    raise Invalid, 'em_andamento' unless Redis::Alfred.set(key, '1', nx: true, ex: LOCK_SECONDS)

    begin
      yield
    ensure
      Redis::Alfred.delete(key)
    end
  end

  # o cliente precisa existir na unidade (a função grava qualquer código, mesmo inexistente)
  def customer!
    builder = Outsider::Erp::QuoteBuilder.new(@budget, document: nil, seller: nil)
    row = @client.query_execute(builder.customer_sql).grep(Hash).first
    raise Invalid, 'cliente_inexistente' unless row

    row
  end

  # cada item vira :part (função do ERP), :service (linha direta, se ligado) ou fica de fora com o motivo
  def plan_lines
    kinds = @catalog.kinds(@budget.company, @budget.items.pluck('codigo'))
    plan = @budget.items.map { |item| plan_line(item, kinds[item['codigo'].to_i]) }
    raise Invalid, 'sem_itens' if plan.none? { |line| line[:kind] != :skip }

    plan
  end

  def plan_line(item, kind)
    return { item: item, kind: :skip, reason: 'inexistente' } if kind.nil?
    return { item: item, kind: :part } unless kind == 1
    return { item: item, kind: :service } if @settings.data['quote_services_direct'] == true

    { item: item, kind: :skip, reason: 'servico' }
  end

  def builder(customer, plan)
    Outsider::Erp::QuoteBuilder.new(@budget, document: customer['documento'], seller: @budget.terms['vendedor'],
                                             service_codes: plan.select { |line| line[:kind] == :service }.map { |line| line[:item]['codigo'].to_i })
  end

  def create_header(customer, plan)
    number = Integer(scalar(@client.query_execute(builder(customer, plan).header_sql)).to_s, exception: false).to_i
    raise Invalid, 'sem_numero' unless number.positive?

    save(erp_number: number, erp_result: @budget.erp_result.merge('progress' => 0))
    log("cabeçalho #{@budget.company}/#{number}")
    number
  end

  # linhas na ordem do rascunho, a partir de onde parou; linha que já está no orçamento (gravada numa tentativa que
  # caiu antes de salvar o avanço) não entra de novo
  def insert_lines(number, plan)
    sendable = plan.reject { |line| line[:kind] == :skip }
    progress = @budget.erp_result['progress'].to_i
    return if progress >= sendable.size

    existing = current_codes(number).tally
    sendable.each_with_index.drop(progress).each do |line, index|
      insert_line(number, line) unless already_in?(existing, sendable, index)
      save(erp_result: @budget.erp_result.merge('progress' => index + 1))
    end
  end

  # a mesma peça pode vir em mais de uma linha: está no ERP se lá já há mais dela do que nas linhas anteriores a esta
  def already_in?(existing, sendable, index)
    code = sendable[index][:item]['codigo'].to_i
    existing.fetch(code, 0) > sendable.first(index).count { |other| other[:item]['codigo'].to_i == code }
  end

  def insert_line(number, line)
    sql_builder = Outsider::Erp::QuoteBuilder.new(@budget, document: nil, seller: nil)
    sql = line[:kind] == :service ? sql_builder.service_sql(number, line[:item]) : sql_builder.item_sql(number, line[:item])
    @client.query_execute(sql)
  end

  # peças que a função do ERP descartou em silêncio (sem NCM para a UF/gênero do cliente): entram direto, sem imposto
  # (Configurações, ligado por padrão). Conta repetidas; rodar de novo só grava o que ainda falta.
  def insert_lost_parts(number, plan, sql_builder)
    return unless @settings.data['quote_parts_direct'] == true

    lost_lines(number, plan).select { |line| line[:kind] == :part }.each do |line|
      @client.query_execute(sql_builder.part_direct_sql(number, line[:item]))
    end
  end

  # Demais Condições e total de serviços: texto do orçamento que as funções não recebem. Falhar aqui não desfaz o
  # orçamento (ele já está certo no ERP); fica o aviso.
  def write_conditions(number, customer, plan)
    columns = Outsider::Erp::Schema.new(@budget.account, client: @client).columns(@budget.company, 'orcamento')
    sql = builder(customer, plan).conditions_sql(number, columns)
    @client.query_execute(sql) if sql
  rescue Outsider::Erp::Client::Error => e
    @conditions_error = e.message
  end

  # o que ficou fora: código inexistente, serviço (se a gravação direta estiver desligada) e o que a função descartou
  # em silêncio (peça sem NCM para a UF do cliente)
  def finish(number, plan)
    skipped = plan.select { |line| line[:kind] == :skip }.map { |line| label(line, line[:reason]) } +
              lost_lines(number, plan).map { |line| label(line, 'ncm') }
    save(status: :created, erp_created_at: Time.current,
         erp_result: { 'skipped' => skipped, 'conditions_error' => @conditions_error }.compact)
    log("gravado #{@budget.company}/#{number}, #{skipped.size} fora")
    @budget
  end

  # linhas mandadas que não estão no orçamento do ERP (conta repetidas)
  def lost_lines(number, plan)
    kept = current_codes(number).tally
    plan.reject { |line| line[:kind] == :skip }.reject do |line|
      code = line[:item]['codigo'].to_i
      kept[code].to_i.positive?.tap { kept[code] = kept[code].to_i - 1 }
    end
  end

  def current_codes(number)
    @client.query_execute(Outsider::Erp::QuoteBuilder.new(@budget, document: nil, seller: nil).lines_sql(number))
           .grep(Hash).map { |row| row['CodigoProduto'].to_i }
  end

  def label(line, reason)
    { 'codigo' => line[:item]['codigo'], 'descricao' => line[:item]['descricao'].to_s.truncate(60), 'motivo' => reason }
  end

  # fora de transação: o número e o avanço precisam ficar salvos mesmo se a próxima chamada ao ERP falhar
  def save(attributes)
    @budget.update_columns(attributes.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
  end

  # primeira coluna da primeira linha devolvida pelo query_execute (as funções voltam [{ "codigo" => N }])
  def scalar(rows)
    row = rows.is_a?(Array) ? rows.first : rows
    row.is_a?(Hash) ? row.values.first : row
  end

  def log(text)
    Rails.logger.info("[Outsider::Erp] conta #{@budget.account_id} usuário #{@user&.id} orçamento #{@budget.id}: #{text}")
  end
end
