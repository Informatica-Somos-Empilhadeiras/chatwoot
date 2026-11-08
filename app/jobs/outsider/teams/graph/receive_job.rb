# OUTSIDER: aviso da Microsoft já conferido (Outsider::TeamsGraphWebhooksController): busca a mensagem no Graph e grava
# na área Teams do colaborador (Outsider::Teams::Graph::Inbound). Roda alguns segundos depois do aviso, para a resposta
# que o próprio Chatwoot mandou já ter o id do Teams gravado.
class Outsider::Teams::Graph::ReceiveJob < ApplicationJob
  queue_as :high

  def perform(subscription_id, resource, change_type = 'created')
    subscription = Outsider::TeamsSubscription.includes(:link).find_by(id: subscription_id)
    link = subscription&.link
    return if link.nil? || link.status != 'active'

    ref = Outsider::Teams::Graph::Inbound.parse(resource)
    return if ref.nil?
    return if ref[:kind] == 'channel' && link.channel_list.none? { |channel| channel['channel_id'] == ref[:channel_id] }

    Outsider::Teams::Graph::Inbound.new(link, ref, change_type).perform
  rescue Outsider::Teams::Graph::Client::Reconnect
    Outsider::Teams::Graph::Notifier.changed(link)
  rescue Outsider::Teams::Graph::Client::Error => e
    # Microsoft ocupada ou fora (429, 5xx, rede): o Sidekiq tenta de novo; recusa definitiva (403...) só fica no log
    raise if e.status.nil? || e.status == 429 || e.status >= 500

    Rails.logger.warn("[outsider_teams_graph] receive skipped: #{e.message}")
  end
end
