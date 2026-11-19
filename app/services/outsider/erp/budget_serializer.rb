# OUTSIDER: o orçamento de peças e serviços (Outsider::Erp::Budget) para a tela: o resumo da lista e o completo do
# editor/envio. "can_edit": rascunho de quem criou ou de um administrador; "stuck": a gravação parou no meio (o job
# morreu) e pode ser pedida de novo.
class Outsider::Erp::BudgetSerializer
  STUCK_AFTER = 3.minutes

  def initialize(account_user, settings = nil)
    @account_user = account_user
    @settings = settings || Outsider::Erp::Settings.new(account_user.account)
  end

  def summary(budget)
    budget.slice(:id, :status, :company, :customer_code, :customer_name, :erp_number, :erp_created_at, :contact_id, :opportunity_id,
                 :created_at, :updated_at).symbolize_keys.merge(state(budget))
  end

  def full(budget)
    result = budget.erp_result.to_h
    summary(budget).merge(
      terms: budget.terms, items: budget.items.map { |item| item.merge('total' => Outsider::Erp::Budget.line_total(item).to_f) },
      skipped: Array(result['skipped']), conditions_error: result['conditions_error'],
      discount: Outsider::Erp::DiscountPolicy.new(budget, @settings).as_json,
      sends: budget.sends.sort_by(&:created_at).reverse.map { |item| send_row(item) }
    )
  end

  def editable?(budget)
    budget.draft? && (@account_user.administrator? || budget.user_id == @account_user.user_id)
  end

  def stuck?(budget) = budget.submitting? && budget.updated_at < STUCK_AFTER.ago

  private

  def state(budget)
    result = budget.erp_result.to_h
    {
      items_count: budget.items.size, total: budget.total.to_f, user: budget.user && { id: budget.user.id, name: budget.user.name },
      error: result['error'], skipped_count: Array(result['skipped']).size, can_edit: editable?(budget), stuck: stuck?(budget),
      sends_count: budget.sends.size, last_send: budget.sends.max_by(&:created_at)&.then { |item| send_row(item) }
    }
  end

  def send_row(item)
    {
      id: item.id, channel: item.channel, recipients: item.recipients, subject: item.subject, status: item.status,
      error: item.error, user: item.user&.name, created_at: item.created_at
    }
  end
end
