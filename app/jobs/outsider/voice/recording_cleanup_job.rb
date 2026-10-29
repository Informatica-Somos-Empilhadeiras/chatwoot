# OUTSIDER: apaga as gravações de ligação mais velhas que o prazo de cada conta (Telefonia > Configurações,
# 1 ano se ninguém mudar; Entrega 25). Roda uma vez por dia, agendado em config/initializers/outsider_voice.rb.
class Outsider::Voice::RecordingCleanupJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where("internal_attributes ? 'outsider_voice'").find_each do |account|
      settings = Outsider::Voice::Settings.new(account)
      Outsider::Voice::Call.where(account_id: account.id, started_at: ...settings.recording_days.days.ago)
                           .joins(:recording_attachment).includes(:recording_attachment).find_each do |call|
        Outsider::Voice::Recording.discard(call)
      end
    end
  end
end
