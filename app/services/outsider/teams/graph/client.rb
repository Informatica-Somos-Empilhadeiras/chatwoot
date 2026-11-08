# OUTSIDER: chamadas ao Microsoft Graph em nome de um colaborador do "Conectar meu Teams". Renova o token sozinho
# (refresh token) e tenta de novo uma vez se a Microsoft responder 401. Quando a Microsoft não aceita mais o acesso
# (senha trocada, acesso revogado, consentimento retirado), a ligação fica 'reconnect' e a pessoa entra de novo.
# O token só vai para graph.microsoft.com.
class Outsider::Teams::Graph::Client
  class Error < StandardError
    attr_reader :status

    def initialize(message, status = nil)
      super(message)
      @status = status
    end
  end

  class Reconnect < Error; end

  V1 = 'https://graph.microsoft.com/v1.0'.freeze
  BETA = 'https://graph.microsoft.com/beta'.freeze
  TIMEOUT = 20

  def self.graph_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host == 'graph.microsoft.com'
  rescue URI::InvalidURIError
    false
  end

  def self.enc(value)
    ERB::Util.url_encode(value.to_s)
  end

  def initialize(link)
    @link = link
  end

  def get(path, beta: false)
    request(:get, path, beta: beta)
  end

  def post(path, body, beta: false)
    request(:post, path, body: body, beta: beta)
  end

  def patch(path, body, beta: false)
    request(:patch, path, body: body, beta: beta)
  end

  def delete(path, beta: false)
    request(:delete, path, beta: beta)
  end

  # arquivo enviado pelo Chatwoot (até 4 MB de uma vez; maiores vão por sessão de envio, ver Files#upload)
  def put_bytes(path, bytes, content_type)
    request(:put, path, raw: bytes, content_type: content_type.presence || 'application/octet-stream')
  end

  # imagem colada no Teams (hostedContents): só de graph.microsoft.com, com o token da pessoa; não grava nada
  def bytes(url, max:)
    raise Error, 'host' unless self.class.graph_url?(url)

    response = raw_get(url)
    if response.code == 401
      @force = true
      refresh!
      response = raw_get(url)
    end
    raise Error.new("graph #{response.code}", response.code) unless response.success?
    raise Error, 'too_big' if response.body.to_s.bytesize > max

    { body: response.body.to_s, content_type: response.headers['content-type'].to_s.split(';').first.presence || 'image/png' }
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end

  def token
    return @link.access_token if @link.token_expires_at.present? && @link.token_expires_at > 2.minutes.from_now &&
                                 @link.access_token.present?

    refresh!
  end

  def refresh!
    @link.with_lock do
      next @link.access_token if @link.token_expires_at.present? && @link.token_expires_at > 2.minutes.from_now && !@force

      app = @link.graph_app
      raise Reconnect, 'no_app' if app.nil?

      tokens = Outsider::Teams::Graph::Login.new(app).refresh(@link.refresh_token)
      @link.update!(access_token: tokens[:access_token], refresh_token: tokens[:refresh_token],
                    token_expires_at: tokens[:expires_at], status: 'active', last_error: nil)
      tokens[:access_token]
    end
  rescue Outsider::Teams::Graph::Login::Error => e
    reconnect!(e.message) if e.message.start_with?('invalid_grant', 'interaction_required', 'invalid_client', 'unauthorized_client')
    raise Error, e.message
  ensure
    @force = false
  end

  private

  def request(method, path, body: nil, beta: false, raw: nil, content_type: nil, retried: false)
    base = beta ? BETA : V1
    url = path.start_with?('https://') ? path : "#{base}#{path}"
    raise Error, 'host' unless self.class.graph_url?(url)

    headers = { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' }
    headers['Content-Type'] = raw ? content_type : 'application/json' if body || raw
    response = HTTParty.send(method, url, headers: headers, body: raw || body&.to_json, timeout: raw ? 120 : TIMEOUT)
    if response.code == 401 && !retried
      @force = true
      refresh!
      return request(method, path, body: body, beta: beta, raw: raw, content_type: content_type, retried: true)
    end
    raise Error.new(error_message(response), response.code) unless response.success?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end

  # o token só vai para o Graph; se a Microsoft mandar para outro endereço dela, segue sem o token
  def raw_get(url)
    response = HTTParty.get(url, headers: { 'Authorization' => "Bearer #{token}" }, timeout: TIMEOUT, follow_redirects: false)
    location = response.headers['location'].to_s
    return response unless response.code.between?(300, 399) && Outsider::Teams::Graph::Files.microsoft_url?(location)

    HTTParty.get(location, timeout: TIMEOUT)
  end

  def error_message(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    detail = error.is_a?(Hash) ? [error['code'], error['message']].compact.join(': ') : error.to_s
    "graph #{response.code}#{" #{detail.first(200)}" if detail.present?}"
  end

  def reconnect!(reason)
    @link.update_columns(status: 'reconnect', last_error: reason.to_s.first(250), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    raise Reconnect, reason
  end
end
