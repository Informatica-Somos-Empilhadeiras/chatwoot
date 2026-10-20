# OUTSIDER: registra na linha do tempo da oportunidade a criação e as mudanças de etapa,
# status e responsável, com quem fez (Current.user) e de onde para onde. O encaminhamento é
# registrado pelo Outsider::Crm::OpportunityForwarder.
module Outsider::Crm::OpportunityTimeline
  extend ActiveSupport::Concern

  included do
    after_create :log_created
    after_update :log_changes
  end

  private

  # Negócio que nasce de um encaminhamento ganha o registro "recebido" (OpportunityForwarder)
  def log_created
    return if forwarded_from_id.present?

    log_activity(:created, stage: stage.name, value_cents: value_cents)
  end

  def log_changes
    log_change(:stage_id, :stage_changed) { |id| Outsider::Crm::Stage.find_by(id: id)&.name }
    # encaminhar registra "encaminhado", com destino e motivo, no lugar da mudança de situação
    log_change(:status, :status_changed) { |value| value } unless forwarded?
    log_change(:owner_id, :owner_changed) { |id| User.find_by(id: id)&.name }
  end

  def log_change(attribute, kind)
    return unless saved_change_to_attribute?(attribute)

    from, to = saved_change_to_attribute(attribute)
    metadata = { from: yield(from), to: yield(to) }
    metadata[:lost_reason] = lost_reason&.name if attribute == :status && lost?
    log_activity(kind, **metadata)
  end

  def log_activity(kind, **metadata)
    activities.create!(account_id: account_id, user: Current.user, kind: kind, metadata: metadata)
  end
end
