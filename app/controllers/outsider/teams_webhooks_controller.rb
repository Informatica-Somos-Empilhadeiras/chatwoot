# OUTSIDER: endereço de mensagens do robô do Microsoft Teams (Entrega 26), configurado no Azure Bot como
# https://<chatwoot>/outsider/teams/<token>/messages. Sem sessão: o token do endereço acha a ligação e a assinatura do
# Bot Framework (Outsider::Teams::Auth) prova que veio da Microsoft. Responde na hora e grava a mensagem num job.
class Outsider::TeamsWebhooksController < ActionController::API
  def create
    connection = Outsider::TeamsConnection.find_by(webhook_token: params[:token].to_s)
    return head :not_found unless connection

    activity = JSON.parse(request.raw_post)
    return head :bad_request unless activity.is_a?(Hash)

    Outsider::Teams::Auth.new(connection).verify!(request.headers['Authorization'], activity)
    Outsider::Teams::ReceiveJob.perform_later(connection.id, activity) if activity['type'] == 'message'
    head :ok
  rescue JSON::ParserError
    head :bad_request
  rescue Outsider::Teams::Auth::Invalid => e
    Rails.logger.warn("[outsider_teams] refused: #{e.message}")
    head :unauthorized
  end
end
