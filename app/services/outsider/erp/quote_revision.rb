# OUTSIDER: abrir e descartar a edição de um orçamento já gravado no ERP (decisão do dono em 20/11/2026: "editar tudo,
# com travas"). Só em NEGOCIAÇÃO e sem ninguém com ele aberto no Mais Prático. Abrir traz do ERP os itens e as condições
# de agora para o registro do chat (status "revising"), e o editor de sempre muda o rascunho; "Salvar no ERP" regrava
# pelo Outsider::Erp::QuoteUpdater. Descartar volta o registro como estava, sem tocar no ERP.
class Outsider::Erp::QuoteRevision
  class Invalid < StandardError; end

  # condições do rascunho que a edição regrava; o resto (cliente, forma de pagamento, frete, gênero) fica como no ERP
  TERMS = %w[vendedor contato observacoes prazo_entrega validade garantia reajuste icms ipi desc_frete armazenagem cancelamento].freeze

  def initialize(account, user)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
  end

  def start(company:, number:, contact: nil, conversation_id: nil)
    raise Invalid, 'quote_write_disabled' unless @settings.quote_write_enabled?

    budget = Outsider::Erp::BudgetImporter.new(@account, @user).import(company: company, number: number, contact: contact,
                                                                       conversation_id: conversation_id)
    return budget if budget.revising? && budget.revision['user_id'] == @user.id
    raise Invalid, 'em_edicao' if budget.revising? || budget.submitting?

    begin_edit(budget)
  end

  # volta como estava antes de abrir a edição (nada foi para o ERP)
  def cancel(budget)
    revision = budget.revision
    raise Invalid, 'not_revising' unless budget.revising? && revision

    budget.update!(status: revision['from'], items: revision['items'] || [], terms: revision['terms'] || {},
                   erp_result: budget.erp_result.except('revision', 'error'))
    budget
  end

  private

  def begin_edit(budget)
    header = editable_header(budget)
    current = Outsider::Erp::BudgetCopy.new(@account).current(budget.company, budget.erp_number)
    terms = budget.terms.merge(current['terms'].slice(*TERMS)).merge('contato' => header['contato'].to_s, 'vendedor' => header['vendedor'])
    budget.update!(status: :revising, customer_code: budget.customer_code || header['cliente_codigo'],
                   erp_result: budget.erp_result.except('error').merge('revision' => revision_for(budget)))
    Outsider::Erp::BudgetForm.new(budget, @settings).apply('terms' => terms, 'items' => current['items'])
  end

  def editable_header(budget)
    header = Outsider::Erp::Records::Detail.new(@account, 'quotes').header_only(budget.company, budget.erp_number)
    raise Invalid, 'status' unless header['status'] == Outsider::Erp::QuoteBuilder::NEGOTIATION
    raise Invalid, 'em_uso' if Outsider::Erp::Records::Detail.in_use?(header)

    header
  end

  # o de antes fica guardado para "Descartar"
  def revision_for(budget)
    { 'from' => budget.status, 'user_id' => @user.id, 'name' => @user.name, 'started_at' => Time.current.iso8601,
      'items' => budget.items, 'terms' => budget.terms }
  end
end
