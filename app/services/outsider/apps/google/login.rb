# OUTSIDER: login da conta Google para o bloco Google dos Aplicativos (OAuth 2.0 do Google, código de autorização, acesso
# offline). O colaborador clica em Conectar, entra na tela do Google e volta para /outsider/google/oauth/callback, que só
# repassa o código para a tela do Chatwoot; a tela manda o código para o servidor com a sessão da pessoa (finish) e o
# servidor troca o código pelos tokens. state é assinado, vale 15 minutos e diz de qual conta e pessoa é o pedido.
#
# Contas Google pessoais (gmail.com): o aplicativo da empresa fica "Externo" e "Em produção" no Google Cloud. Sem a
# verificação do Google aparece uma vez o aviso "o Google não verificou este app" (Avançado > Acessar) e o limite é de
# 100 pessoas; em "Teste" o Google derruba o login a cada 7 dias.
class Outsider::Apps::Google::Login
  class Error < StandardError; end

  AUTH = 'https://accounts.google.com/o/oauth2/v2/auth'.freeze
  TOKEN = 'https://oauth2.googleapis.com/token'.freeze
  REVOKE = 'https://oauth2.googleapis.com/revoke'.freeze
  USERINFO = 'https://openidconnect.googleapis.com/v1/userinfo'.freeze
  CALLBACK_PATH = '/outsider/google/oauth/callback'.freeze
  # Gmail (ler, organizar e mandar; a lixeira do Gmail continua valendo), Agenda (ver e marcar eventos) e Drive (ver,
  # mandar e organizar os arquivos da pessoa)
  SCOPES = (%w[openid email profile] + Outsider::GoogleLink::FEATURES.values).freeze
  STATE_PURPOSE = 'outsider_google_oauth'.freeze
  TIMEOUT = 15

  def self.site
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  def self.redirect_uri
    "#{site}#{CALLBACK_PATH}"
  end

  def self.verifier
    Rails.application.message_verifier(STATE_PURPOSE)
  end

  # { 'a' => account_id, 'u' => user_id } ou nil
  def self.read_state(state)
    data = verifier.verified(state.to_s)
    data.is_a?(Hash) ? data.stringify_keys : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def initialize(app)
    @app = app
  end

  # prompt consent: o Google só manda o refresh token (acesso quando a pessoa não está na tela) quando pede a permissão
  def authorize_url(user)
    query = { client_id: @app.client_id, redirect_uri: self.class.redirect_uri, response_type: 'code', scope: SCOPES.join(' '),
              access_type: 'offline', prompt: 'consent select_account', include_granted_scopes: 'true',
              state: self.class.verifier.generate({ 'a' => @app.account_id, 'u' => user.id }, expires_in: 15.minutes) }
    "#{AUTH}?#{query.to_query}"
  end

  # { access_token:, refresh_token:, expires_at:, scopes: }
  def exchange(code)
    token_request(grant_type: 'authorization_code', code: code.to_s, redirect_uri: self.class.redirect_uri)
  end

  def refresh(refresh_token)
    token_request(grant_type: 'refresh_token', refresh_token: refresh_token.to_s)
  end

  # { sub:, email:, name: } da conta que entrou
  def profile(access_token)
    response = HTTParty.get(USERINFO, headers: { 'Authorization' => "Bearer #{access_token}" }, timeout: TIMEOUT)
    body = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    raise Error, "userinfo_#{response.code}" unless response.success? && body['sub'].present?

    { sub: body['sub'].to_s, email: body['email'].to_s, name: body['name'].to_s }
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end

  # desconectar: tira o acesso do Chatwoot na conta Google também (se falhar, a pessoa tira em myaccount.google.com)
  def self.revoke(token)
    return if token.blank?

    HTTParty.post(REVOKE, body: { token: token }, timeout: TIMEOUT)
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout
    nil
  end

  private

  def token_request(params)
    response = HTTParty.post(TOKEN, body: params.merge(client_id: @app.client_id, client_secret: @app.client_secret),
                                    timeout: TIMEOUT)
    body = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    raise Error, [body['error'] || "http_#{response.code}", body['error_description']].compact.join(': ').first(300) unless
      response.success? && body['access_token'].present?

    { access_token: body['access_token'], refresh_token: body['refresh_token'], scopes: body['scope'].to_s,
      expires_at: Time.current + body['expires_in'].to_i.seconds }
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end
end
