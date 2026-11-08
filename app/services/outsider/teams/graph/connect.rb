# OUTSIDER: termina o "Entrar com a conta Microsoft" de um colaborador: troca o código pelos tokens, lê quem entrou
# (/me) e cria ou atualiza a ligação dele. A mesma conta Microsoft não pode ficar ligada a duas pessoas do Chatwoot.
# Trocou de conta Microsoft: a área Teams começa do zero (as conversas da conta antiga saem).
class Outsider::Teams::Graph::Connect
  class Error < StandardError; end

  def initialize(app, user)
    @app = app
    @user = user
  end

  def perform(code)
    tokens = Outsider::Teams::Graph::Login.new(@app).exchange(code)
    me = profile(tokens[:access_token])
    other = Outsider::TeamsLink.where(account_id: @app.account_id, ms_user_id: me['id']).where.not(user_id: @user.id).first
    raise Error, "already_linked:#{other.user&.name}" if other

    link = Outsider::TeamsLink.find_or_initialize_by(account_id: @app.account_id, user_id: @user.id)
    if link.persisted? && link.ms_user_id != me['id']
      Outsider::Teams::Graph::Subscriptions.new(link).remove_all!
      link.threads.destroy_all
      link.channels = []
    end
    link.assign_attributes(ms_user_id: me['id'], ms_tenant_id: @app.tenant_id, display_name: me['displayName'],
                           email: me['mail'].presence || me['userPrincipalName'], access_token: tokens[:access_token],
                           refresh_token: tokens[:refresh_token], token_expires_at: tokens[:expires_at], status: 'active',
                           last_error: nil)
    link.save!
    Outsider::Teams::Graph::Subscriptions.new(link).plan!
    Outsider::Teams::Graph::SyncJob.perform_later(link.id)
    link
  rescue Outsider::Teams::Graph::Login::Error => e
    raise Error, e.message
  end

  private

  def profile(token)
    response = HTTParty.get('https://graph.microsoft.com/v1.0/me?$select=id,displayName,mail,userPrincipalName',
                            headers: { 'Authorization' => "Bearer #{token}" }, timeout: 15)
    raise Error, "profile #{response.code}" unless response.success? && response.parsed_response.is_a?(Hash)

    response.parsed_response
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end
end
