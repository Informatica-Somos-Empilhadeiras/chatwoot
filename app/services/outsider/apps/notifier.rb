# OUTSIDER: aviso ao vivo para a tela de uma pessoa sobre os aplicativos (Outlook, Gmail...): evento outsider.notice com
# kind 'apps', só no canal pessoal dela no ActionCable. A tela atualiza o número do menu e a lista aberta.
module Outsider::Apps::Notifier
  module_function

  def broadcast(user, account_id, data)
    token = user&.pubsub_token
    return if token.blank?

    ActionCable.server.broadcast(token, { event: 'outsider.notice', data: data.merge(account_id: account_id, kind: 'apps') })
  rescue StandardError => e
    Rails.logger.warn("[outsider_apps] live update failed: #{e.message}")
  end
end
