# OUTSIDER: mensagem do Teams já conferida pelo webhook (Outsider::TeamsWebhooksController), gravada fora da requisição
# para o Teams ter a resposta na hora (ele espera no máximo 15 s).
class Outsider::Teams::ReceiveJob < ApplicationJob
  queue_as :high

  def perform(connection_id, activity)
    connection = Outsider::TeamsConnection.find_by(id: connection_id)
    Outsider::Teams::Inbound.new(connection, activity).perform if connection
  end
end
