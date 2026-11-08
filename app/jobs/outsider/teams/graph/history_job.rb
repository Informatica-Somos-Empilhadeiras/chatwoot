# OUTSIDER: traz as mensagens antigas dos chats e dos canais que acabaram de entrar (Outsider::Teams::Graph::History).
class Outsider::Teams::Graph::HistoryJob < ApplicationJob
  queue_as :low

  def perform(link_id)
    link = Outsider::TeamsLink.find_by(id: link_id)
    return unless link&.status == 'active'

    Outsider::Teams::Graph::History.new(link).perform
    Outsider::Teams::Graph::Notifier.changed(link)
  rescue Outsider::Teams::Graph::Client::Reconnect
    Outsider::Teams::Graph::Notifier.changed(link)
  end
end
