# OUTSIDER: mantém status e etapa da oportunidade coerentes. Ir para uma etapa de ganho ou
# perda fecha a oportunidade; marcar como ganha ou perdida leva para a etapa final do
# pipeline, quando existir. Reabrir volta para a primeira etapa aberta.
module Outsider::Crm::OpportunityLifecycle
  extend ActiveSupport::Concern

  CLOSED = %w[won lost].freeze

  included do
    validate :lost_reason_when_lost
    before_validation :sync_status_and_stage
    before_save :track_closing
  end

  private

  def sync_status_and_stage
    return if stage.blank? || pipeline.blank?

    if will_save_change_to_stage_id? && !will_save_change_to_status?
      self.status = stage.kind_open? ? :open : stage.kind
    elsif will_save_change_to_status?
      move_to_stage_for_status
    end
  end

  def move_to_stage_for_status
    if CLOSED.include?(status)
      final_stage = pipeline.stages.find_by(kind: status)
      self.stage = final_stage if final_stage && stage.kind != status
    elsif open? && !stage.kind_open?
      self.stage = pipeline.first_open_stage || stage
    end
  end

  def track_closing
    return unless will_save_change_to_status?

    self.closed_at = open? ? nil : Time.current
    self.lost_reason = nil unless lost? || forwarded?
  end

  # Só exige motivo se a conta cadastrou algum motivo de perda
  def lost_reason_when_lost
    return unless lost? && lost_reason.blank?
    return unless Outsider::Crm::LostReason.active.exists?(account_id: account_id, kind: [:lost, :both])

    errors.add(:lost_reason, :blank)
  end
end
