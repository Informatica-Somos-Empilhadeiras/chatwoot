# OUTSIDER: grava no ERP uma OS feita no chat (Outsider::Erp::Orders::Creator) fora da requisição: são várias chamadas ao
# ERP (cabeçalho, histórico, uma por linha, orçamento) e a produção corta requisição em 15 s. A tela acompanha pelo
# status "submitting". Falhou: volta a rascunho com o motivo; o que já entrou no ERP fica (com a marca do rascunho) e a
# próxima tentativa continua de onde parou.
class Outsider::Erp::OrderSubmitJob < ApplicationJob
  queue_as :default

  def perform(draft_id, user_id)
    draft = Outsider::Erp::OrderDraft.find_by(id: draft_id)
    return unless draft&.submitting?

    Outsider::Erp::Orders::Creator.new(draft, user: User.find_by(id: user_id)).call
  rescue Outsider::Erp::Orders::Creator::Disabled
    fail_with(draft, 'order_write_disabled')
  rescue Outsider::Erp::Orders::Creator::Invalid, Outsider::Erp::Client::Error, ArgumentError => e
    fail_with(draft, e.message)
  rescue StandardError
    fail_with(draft, 'erro_interno')
    raise
  end

  private

  def fail_with(draft, reason)
    return unless draft

    draft.reload
    return unless draft.submitting?

    draft.update_columns(status: Outsider::Erp::OrderDraft.statuses[:draft], updated_at: Time.current, # rubocop:disable Rails/SkipsModelValidations
                         erp_result: draft.erp_result.to_h.merge('error' => reason.to_s.first(200)))
  end
end
