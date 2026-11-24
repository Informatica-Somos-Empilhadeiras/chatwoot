# OUTSIDER: a cada 5 minutos, o observador do Gmail de cada pessoa conectada ao bloco Google (Outsider::Apps::Google::
# Watcher), uma pessoa depois da outra e um pedido pequeno para cada: quase nada de processamento e memória. Quem
# perdeu o acesso (senha trocada, acesso retirado) fica 'reconnect' e sai da lista até entrar de novo.
class Outsider::Apps::Google::WatchJob < ApplicationJob
  queue_as :scheduled_jobs

  # se duas rodadas se encontrarem (fila atrasada), a segunda pula quem acabou de ser olhado
  RECENT = 4.minutes

  def perform
    Outsider::GoogleLink.active.where('checked_at IS NULL OR checked_at < ?', RECENT.ago).find_each do |link|
      next unless link.allows?(:mail)

      Outsider::Apps::Google::Watcher.new(link).perform
    rescue Outsider::Apps::Google::Client::Reconnect
      Outsider::Apps::Notifier.broadcast(link.user, link.account_id, provider: 'google', app: 'mail', action: 'reconnect')
    rescue Outsider::Apps::Google::Client::Error => e
      Rails.logger.warn("[outsider_google] watch link #{link.id}: #{e.message}")
    end
  end
end
