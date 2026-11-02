# OUTSIDER: o que sai numa caixa do Microsoft Teams vai para o Teams (Entrega 26). Incluído no AsyncDispatcher pelo
# config/initializers/outsider_teams.rb, roda no Sidekiq. Só mensagem enviada e pública (nota privada fica no Chatwoot).
class Outsider::TeamsListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return unless message.outgoing? && !message.private? && message.source_id.blank?
    return unless Outsider::TeamsConnection.exists?(inbox_id: message.inbox_id)

    Outsider::Teams::SendJob.perform_later(message.id)
  end
end
