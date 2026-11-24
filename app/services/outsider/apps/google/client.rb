# OUTSIDER: chamadas às APIs do Google (Gmail, Agenda e Drive) em nome de um colaborador do bloco Google. Renova o token
# sozinho (refresh token, a cada hora) e tenta de novo uma vez se o Google responder 401. Quando o Google não aceita
# mais o acesso (senha trocada, acesso retirado em myaccount.google.com), a ligação fica 'reconnect' e a pessoa entra de
# novo. O token só vai para *.googleapis.com (e para a miniatura do Drive, em *.googleusercontent.com).
#
# Os erros são os mesmos do Microsoft Graph (Error com status, Reconnect), para as telas tratarem igual.
class Outsider::Apps::Google::Client
  Error = Outsider::Teams::Graph::Client::Error
  Reconnect = Outsider::Teams::Graph::Client::Reconnect

  GMAIL = 'https://gmail.googleapis.com/gmail/v1/users/me'.freeze
  GMAIL_UPLOAD = 'https://gmail.googleapis.com/upload/gmail/v1/users/me'.freeze
  GMAIL_BATCH = 'https://gmail.googleapis.com/batch/gmail/v1'.freeze
  CALENDAR = 'https://www.googleapis.com/calendar/v3'.freeze
  DRIVE = 'https://www.googleapis.com/drive/v3'.freeze
  DRIVE_UPLOAD = 'https://www.googleapis.com/upload/drive/v3'.freeze
  TIMEOUT = 20
  BATCH_MAX = 50
  # o Google responde 403 com estes motivos quando é excesso de pedidos (vira "busy", não "forbidden")
  RATE_REASONS = %w[rateLimitExceeded userRateLimitExceeded quotaExceeded dailyLimitExceeded].freeze

  def self.google_url?(url, hosts: %w[googleapis.com])
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && hosts.any? { |host| uri.host.to_s == host || uri.host.to_s.end_with?(".#{host}") }
  rescue URI::InvalidURIError
    false
  end

  def self.enc(value)
    ERB::Util.url_encode(value.to_s)
  end

  def initialize(link)
    @link = link
  end

  def get(url, query: nil)
    request(:get, url, query: query)
  end

  def post(url, body, query: nil)
    request(:post, url, body: body, query: query)
  end

  def patch(url, body, query: nil)
    request(:patch, url, body: body, query: query)
  end

  def delete(url, query: nil)
    request(:delete, url, query: query)
  end

  # corpo pronto (envio de e-mail e de arquivo): devolve a resposta inteira (cabeçalhos, código)
  def raw(method, url, body:, content_type:, query: nil, headers: {}, timeout: 120)
    send_request(method, url, query: query, raw: body, content_type: content_type, extra: headers, timeout: timeout,
                              full: true)
  end

  # Gmail em lote: até 50 GETs num pedido só (paths relativos, ex.: "/gmail/v1/users/me/messages/ID?format=metadata").
  # Devolve um array na mesma ordem, com o JSON de cada um ou nil quando aquele falhou.
  def batch(paths, endpoint: GMAIL_BATCH)
    paths.each_slice(BATCH_MAX).flat_map { |slice| batch_slice(slice, endpoint) }
  end

  # arquivo aos pedaços, direto do Google para quem pediu (nada fica no disco nem inteiro na memória)
  def stream(url, query: nil, &)
    full = with_query(url, query)
    raise Error, 'host' unless self.class.google_url?(full)

    response = stream_get(full, &)
    if response.code == 401
      @force = true
      refresh!
      response = stream_get(full, &)
    end
    raise Error.new("google #{response.code}", response.code) unless response.code.between?(200, 299)
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    raise Error, e.message.first(200)
  end

  # bytes pequenos (miniatura do Drive, até max): só de googleapis.com/googleusercontent.com
  def bytes(url, max:)
    raise Error, 'host' unless self.class.google_url?(url, hosts: %w[googleapis.com googleusercontent.com])

    response = HTTParty.get(url, headers: { 'Authorization' => "Bearer #{token}" }, timeout: TIMEOUT)
    raise Error.new("google #{response.code}", response.code) unless response.success?
    raise Error, 'too_big' if response.body.to_s.bytesize > max

    { body: response.body.to_s, content_type: response.headers['content-type'].to_s.split(';').first.presence || 'image/png' }
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message.first(200)
  end

  def token
    return @link.access_token if fresh?

    refresh!
  end

  def refresh!
    @link.with_lock do
      next @link.access_token if fresh? && !@force

      app = @link.app
      raise Reconnect, 'no_app' if app.nil?

      tokens = Outsider::Apps::Google::Login.new(app).refresh(@link.refresh_token)
      attributes = { access_token: tokens[:access_token], token_expires_at: tokens[:expires_at], status: 'active', last_error: nil }
      attributes[:refresh_token] = tokens[:refresh_token] if tokens[:refresh_token].present?
      attributes[:scopes] = tokens[:scopes] if tokens[:scopes].present?
      @link.update!(attributes)
      tokens[:access_token]
    end
  rescue Outsider::Apps::Google::Login::Error => e
    reconnect!(e.message) if e.message.start_with?('invalid_grant', 'invalid_client', 'unauthorized_client')
    raise Error, e.message
  ensure
    @force = false
  end

  private

  # o Google quer a chave repetida para listas (labelIds=INBOX&labelIds=UNREAD), não labelIds[]=
  def with_query(url, query)
    pairs = query.to_h.compact.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
    return url if pairs.empty?

    "#{url}#{url.include?('?') ? '&' : '?'}#{URI.encode_www_form(pairs)}"
  end

  def stream_get(full)
    HTTParty.get(full, headers: { 'Authorization' => "Bearer #{token}" }, stream_body: true, timeout: 60) do |fragment|
      yield fragment.to_s if fragment.code.between?(200, 299)
    end
  end

  def fresh?
    @link.token_expires_at.present? && @link.token_expires_at > 2.minutes.from_now && @link.access_token.present?
  end

  def request(method, url, body: nil, query: nil)
    send_request(method, url, body: body, query: query)
  end

  def send_request(method, url, body: nil, query: nil, raw: nil, content_type: nil, extra: {}, timeout: TIMEOUT, full: false,
                   retried: false)
    address = with_query(url, query)
    raise Error, 'host' unless self.class.google_url?(address)

    headers = extra.to_h.transform_keys(&:to_s).except('Authorization')
    headers['Authorization'] = "Bearer #{token}"
    headers['Accept'] ||= 'application/json'
    headers['Content-Type'] = raw ? content_type : 'application/json' if body || raw
    response = HTTParty.send(method, address, headers: headers, body: raw || body&.to_json, timeout: timeout,
                                              follow_redirects: false)
    if response.code == 401 && !retried
      @force = true
      refresh!
      return send_request(method, url, body: body, query: query, raw: raw, content_type: content_type, extra: extra,
                                       timeout: timeout, full: full, retried: true)
    end
    raise_error(response) unless response.code.between?(200, 299) || (full && response.code == 308)
    return response if full

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    raise Error, e.message.first(200)
  end

  def raise_error(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    reasons = error.is_a?(Hash) ? Array(error['errors']).filter_map { |item| item['reason'] if item.is_a?(Hash) } : []
    detail = error.is_a?(Hash) ? [error['status'], error['message']].compact.join(': ') : error.to_s
    status = response.code == 403 && reasons.intersect?(RATE_REASONS) ? 429 : response.code
    raise Error.new("google #{response.code}#{" #{detail.first(200)}" if detail.present?}", status)
  end

  def batch_slice(paths, endpoint)
    boundary = "outsider_#{SecureRandom.hex(10)}"
    body = paths.each_with_index.map do |path, index|
      "--#{boundary}\r\nContent-Type: application/http\r\nContent-ID: <item#{index}>\r\n\r\nGET #{path}\r\n\r\n"
    end.join + "--#{boundary}--"
    response = send_request(:post, endpoint, raw: body, content_type: "multipart/mixed; boundary=#{boundary}", full: true)
    parse_batch(response, paths.size)
  end

  # resposta do lote: multipart/mixed, cada parte é um "HTTP/1.1 200 OK" com o JSON; Content-ID diz de qual pedido é
  def parse_batch(response, size)
    results = Array.new(size)
    boundary = response.headers['content-type'].to_s[/boundary="?([^";]+)"?/, 1]
    return results if boundary.blank?

    response.body.to_s.split("--#{boundary}").each do |part|
      index = part[/Content-ID:\s*<?response-item(\d+)>?/i, 1]
      next if index.nil? || index.to_i >= size

      http = part.split(/\r?\n\r?\n/, 2).last.to_s
      status = http[%r{\AHTTP/[\d.]+ (\d{3})}, 1].to_i
      json = http.split(/\r?\n\r?\n/, 2).last.to_s.strip
      next unless status.between?(200, 299)

      results[index.to_i] = JSON.parse(json)
    rescue JSON::ParserError
      next
    end
    results
  end

  def reconnect!(reason)
    @link.update_columns(status: 'reconnect', last_error: reason.to_s.first(250), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    raise Reconnect, reason
  end
end
