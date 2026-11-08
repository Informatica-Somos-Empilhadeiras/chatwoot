# OUTSIDER: de hora em hora, renova os avisos da Microsoft do "Conectar meu Teams" que vencem em menos de 30 horas e
# recria os que faltam (por exemplo, o Chatwoot ficou fora do ar). Também mantém o login vivo: renovar usa o token.
# No modo "Todos os canais" confere se entrou ou saiu canal nas equipes da pessoa.
class Outsider::Teams::Graph::RenewJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Outsider::TeamsLink.active.find_each do |link|
      # "Todos os canais": canal novo (ou que saiu) nas equipes da pessoa -> acerta avisos e traz as mensagens antigas
      Outsider::Teams::Graph::SyncJob.perform_later(link.id) if Outsider::Teams::Graph::AutoChannels.new(link).refresh!
      subscriptions = Outsider::Teams::Graph::Subscriptions.new(link)
      link.subscriptions.each do |subscription|
        next if subscription.subscription_id.present? && subscription.expires_at.present? &&
                subscription.expires_at > Outsider::Teams::Graph::Subscriptions::RENEW_BEFORE.from_now

        subscriptions.renew(subscription)
      end
    rescue Outsider::Teams::Graph::Client::Reconnect
      Outsider::Teams::Graph::Notifier.changed(link)
    rescue Outsider::Teams::Graph::Client::Error => e
      Rails.logger.warn("[outsider_teams_graph] renew link #{link.id}: #{e.message}")
    end
  end
end
