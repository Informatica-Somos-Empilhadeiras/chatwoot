# OUTSIDER: login da conta Microsoft para o "Conectar meu Teams" (OAuth 2.0 do Microsoft Entra ID, código de autorização).
# O colaborador clica em Conectar, entra na tela da Microsoft e volta para /outsider/teams/oauth/callback, que devolve
# o código para a tela do Chatwoot; a tela manda o código para o servidor com a sessão da pessoa (finish), e o servidor
# troca o código pelos tokens. state é assinado e vale 15 minutos, e diz de qual conta e pessoa é o pedido.
# O administrador da empresa pode dar o consentimento por todos pelo admin_consent_url (uma vez só).
class Outsider::Teams::Graph::Login
  class Error < StandardError; end

  LOGIN = 'https://login.microsoftonline.com'.freeze
  GRAPH = 'https://graph.microsoft.com'.freeze
  CALLBACK_PATH = '/outsider/teams/oauth/callback'.freeze
  # Graph: chats (ler, responder), equipes e canais (listar, ler, responder), o perfil da pessoa e os arquivos dela
  # (ver e mandar arquivos pelo OneDrive/SharePoint, como o Teams faz)
  PERMISSIONS = %w[User.Read Chat.ReadWrite ChatMessage.Send Team.ReadBasic.All Channel.ReadBasic.All ChannelMessage.Read.All
                   ChannelMessage.Send Files.ReadWrite.All].freeze
  SCOPES = (%w[offline_access openid profile email] + PERMISSIONS).freeze
  STATE_PURPOSE = 'outsider_teams_oauth'.freeze
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

  # { 'a' => account_id, 'u' => user_id, 'k' => 'login' | 'consent' } ou nil
  def self.read_state(state)
    data = verifier.verified(state.to_s)
    data.is_a?(Hash) ? data.stringify_keys : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def initialize(app)
    @app = app
  end

  def authorize_url(user)
    query = { client_id: @app.client_id, response_type: 'code', response_mode: 'query', redirect_uri: self.class.redirect_uri,
              scope: SCOPES.join(' '), state: state(user, 'login'), prompt: 'select_account', login_hint: user.email }
    "#{LOGIN}/#{@app.tenant_id}/oauth2/v2.0/authorize?#{query.compact.to_query}"
  end

  # consentimento do administrador do Microsoft 365 por toda a empresa (as permissões vão na própria URL)
  def admin_consent_url(user)
    query = { client_id: @app.client_id, redirect_uri: self.class.redirect_uri, state: state(user, 'consent'),
              scope: PERMISSIONS.map { |permission| "#{GRAPH}/#{permission}" }.join(' ') }
    "#{LOGIN}/#{@app.tenant_id}/v2.0/adminconsent?#{query.to_query}"
  end

  def exchange(code)
    token_request(grant_type: 'authorization_code', code: code.to_s, redirect_uri: self.class.redirect_uri)
  end

  def refresh(refresh_token)
    token_request(grant_type: 'refresh_token', refresh_token: refresh_token.to_s)
  end

  private

  def state(user, kind)
    self.class.verifier.generate({ 'a' => @app.account_id, 'u' => user.id, 'k' => kind }, expires_in: 15.minutes)
  end

  # { access_token:, refresh_token:, expires_at: } ou Error com o código da Microsoft (invalid_grant = entrar de novo)
  def token_request(params)
    response = HTTParty.post("#{LOGIN}/#{@app.tenant_id}/oauth2/v2.0/token",
                             body: params.merge(client_id: @app.client_id, client_secret: @app.client_secret,
                                                scope: SCOPES.join(' ')),
                             timeout: TIMEOUT)
    body = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    raise Error, [body['error'] || "http_#{response.code}", body['error_description'].to_s.lines.first&.strip].compact.join(': ') unless
      response.success? && body['access_token'].present?

    { access_token: body['access_token'], refresh_token: body['refresh_token'],
      expires_at: Time.current + body['expires_in'].to_i.seconds }
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end
end
