# OUTSIDER: grava no ERP um orçamento de peças e serviços (Outsider::Erp::QuoteCreator) fora da requisição: são várias
# chamadas ao ERP (uma por linha) e a produção corta requisição em 15 s. A tela acompanha pelo status "submitting".
# Falhou: volta a rascunho com o motivo; o que já entrou no ERP fica e a próxima tentativa continua de onde parou.
class Outsider::Erp::BudgetSubmitJob < ApplicationJob
  queue_as :default

  def perform(budget_id, user_id)
    budget = Outsider::Erp::Budget.find_by(id: budget_id)
    return unless budget&.submitting?

    Outsider::Erp::QuoteCreator.new(budget, user: User.find_by(id: user_id)).call
  rescue Outsider::Erp::QuoteCreator::Disabled
    fail_with(budget, 'quote_write_disabled')
  rescue Outsider::Erp::QuoteCreator::Invalid, Outsider::Erp::Client::Error, ArgumentError => e
    fail_with(budget, e.message)
  rescue StandardError
    fail_with(budget, 'erro_interno')
    raise
  end

  private

  def fail_with(budget, reason)
    return unless budget

    budget.reload
    return if budget.created?

    budget.update_columns(status: Outsider::Erp::Budget.statuses[:draft], updated_at: Time.current, # rubocop:disable Rails/SkipsModelValidations
                          erp_result: budget.erp_result.merge('error' => reason.to_s.first(200)))
  end
end
