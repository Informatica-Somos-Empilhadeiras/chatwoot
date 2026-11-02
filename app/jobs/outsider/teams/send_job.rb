# OUTSIDER: resposta da caixa do Teams indo para o Teams (Outsider::Teams::Outbound), avisada pelo Outsider::TeamsListener.
class Outsider::Teams::SendJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.find_by(id: message_id)
    connection = message && Outsider::TeamsConnection.find_by(inbox_id: message.inbox_id)
    return if connection.nil? || message.source_id.present?

    Outsider::Teams::Outbound.new(connection, message).perform
  end
end
