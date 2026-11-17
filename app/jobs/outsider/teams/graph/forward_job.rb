# OUTSIDER: encaminhar da área Teams (Outsider::Teams::Graph::Forward): manda as mensagens de um destino em ordem.
class Outsider::Teams::Graph::ForwardJob < ApplicationJob
  queue_as :default

  def perform(message_ids)
    Outsider::TeamsMessage.where(id: message_ids).order(:id).each do |message|
      Outsider::Teams::Graph::Forward.new(message).deliver
    rescue StandardError => e
      Rails.logger.error("[outsider_teams_forward] message=#{message.id} #{e.class}: #{e.message}")
      message.update!(status: 'failed', error: e.message.first(250)) if message.reload.status == 'sending'
      Outsider::Teams::Graph::Notifier.message(message.thread.link, message.thread, message, action: 'updated')
    end
  end
end
