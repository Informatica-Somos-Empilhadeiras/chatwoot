# OUTSIDER: deixa a área Teams da pessoa igual ao que ela escolheu, fora da tela: no modo "Todos os canais" relê os canais
# na Microsoft, pede os avisos de mensagem nova (cada um leva alguns segundos, porque a Microsoft confere o endereço do
# Chatwoot antes de aceitar; com vários canais, fazer isso ao salvar passava do tempo da página) e depois traz as
# mensagens antigas (Outsider::Teams::Graph::HistoryJob). No fim avisa a tela da pessoa para mostrar o resultado.
class Outsider::Teams::Graph::SyncJob < ApplicationJob
  queue_as :default

  def perform(link_id)
    link = Outsider::TeamsLink.find_by(id: link_id)
    return unless link&.status == 'active'

    refresh_channels(link)
    Outsider::Teams::Graph::Subscriptions.new(link).sync!
    Outsider::Teams::Graph::HistoryJob.perform_later(link.id)
  rescue Outsider::Teams::Graph::Client::Reconnect
    nil
  ensure
    Outsider::Teams::Graph::Notifier.changed(link) if link
  end

  private

  def refresh_channels(link)
    Outsider::Teams::Graph::AutoChannels.new(link).refresh!
  rescue Outsider::Teams::Graph::Client::Reconnect
    raise
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_teams_graph] channels link #{link.id}: #{e.message}")
  end
end
