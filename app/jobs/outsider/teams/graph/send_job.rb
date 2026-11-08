# OUTSIDER: mensagem escrita na área Teams indo para o Teams (Outsider::Teams::Graph::Outbound).
class Outsider::Teams::Graph::SendJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Outsider::TeamsMessage.find_by(id: message_id)
    return if message.nil? || message.status != 'sending'

    Outsider::Teams::Graph::Outbound.new(message).perform
  end
end
