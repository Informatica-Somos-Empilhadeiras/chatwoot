# OUTSIDER: o rascunho de OS do chat (Outsider::Erp::OrderDraft) como a tela usa: resumo para a lista e completo para a
# gaveta (campos, itens, conferência, passos feitos, leitura de volta e o erro da última tentativa).
class Outsider::Erp::Orders::Serializer
  STUCK_AFTER = 3.minutes

  def initialize(account_user)
    @account_user = account_user
  end

  def summary(draft)
    result = draft.erp_result.to_h
    {
      id: draft.id, kind: draft.kind, status: draft.status, company: draft.company, customer_code: draft.customer_code,
      customer_name: draft.customer_name, quote_number: draft.quote_number, erp_number: draft.erp_number,
      contact_id: draft.contact_id, conversation_id: draft.conversation_id, items_count: draft.items.size, total: draft.total.to_f,
      tipo_atendimento: draft.fields['tipo_atendimento'], user: draft.user && { id: draft.user.id, name: draft.user.name },
      error: result['error'], cancelled: draft.cancelled?, can_edit: editable?(draft), stuck: stuck?(draft),
      erp_created_at: draft.erp_created_at, created_at: draft.created_at, updated_at: draft.updated_at
    }
  end

  def full(draft)
    result = draft.erp_result.to_h
    summary(draft).merge(
      fields: draft.fields, items: draft.items, checks: Array(result['checks']), steps: draft.steps, readback: result['readback'],
      schedule_error: result['schedule_error'], cancelled_at: result['cancelled_at'], can_submit: submittable?(draft),
      can_cancel: cancellable?(draft)
    )
  end

  # muda o rascunho: quem criou ou um administrador, só antes de ter número no ERP
  def editable?(draft) = draft.draft? && !draft.in_erp? && owner?(draft)

  # gravar (ou continuar uma gravação que parou no meio)
  def submittable?(draft) = owner?(draft) && !draft.cancelled? && (draft.draft? || stuck?(draft))

  # "Cancelar OS": a OS já tem número no ERP, a gravação não está rodando e ainda não foi cancelada
  def cancellable?(draft) = owner?(draft) && draft.in_erp? && !draft.cancelled? && !draft.submitting?

  def stuck?(draft) = draft.submitting? && draft.updated_at < STUCK_AFTER.ago

  def owner?(draft) = @account_user.administrator? || draft.user_id == @account_user.user_id
end
