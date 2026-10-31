# OUTSIDER: chamada HTTP de uma conexão do bot (Outsider::Bot::Connection). O endereço é sempre o da
# conexão: o caminho do bloco só acrescenta pasta e parâmetros, e o servidor final é conferido.
#
# Leve de propósito: nada fica aberto entre uma chamada e outra, tempo limite em cada uma (o da conexão,
# até 30 s), resposta de no máximo 1 MB lida em pedaços (passou disso, para) e o token do OAuth2 guardado
# no Redis, criptografado, até vencer. POST, PUT, PATCH e DELETE só com "permite alterar dados".
class Outsider::Bot::Integrations::Http
  METHODS = %w[GET POST PUT PATCH DELETE].freeze
  WRITE_METHODS = %w[POST PUT PATCH DELETE].freeze
  DAV_METHODS = %w[PROPFIND SEARCH].freeze
  MAX_BODY = 1.megabyte
  OPEN_TIMEOUT = 5
  MAX_REDIRECTS = 3
  OAUTH_KEY = 'OUTSIDER::BOT::OAUTH::%<id>d::%<version>d'.freeze
  USER_AGENT = 'Chatwoot-Somos-Bot/1.0'.freeze
  NETWORK_ERRORS = [SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse, Zlib::Error].freeze

  class Error < StandardError
    attr_reader :code

    def initialize(code, message = nil)
      @code = code
      super(message || code)
    end
  end

  Response = Struct.new(:status, :body, :content_type, :duration_ms, :url, :cached, keyword_init: true) do
    def success?
      status.to_i.between?(200, 299)
    end

    # JSON, XML (vira objeto) ou nil
    def data
      return @data if defined?(@data)

      @data = Outsider::Bot::Integrations::Http.parse(body.to_s, content_type.to_s)
    end
  end

  def self.parse(body, content_type)
    text = body.strip
    return if text.empty?

    if content_type.include?('json') || text.start_with?('{', '[')
      JSON.parse(text)
    elsif content_type.include?('xml') || text.start_with?('<')
      Hash.from_xml(text)
    end
  rescue StandardError
    nil
  end

  def initialize(connection)
    @connection = connection
  end

  # path relativo ao endereço da conexão (pode trazer ?a=1); query, headers e body já com as variáveis trocadas
  # write: nil decide pelo método; uma consulta GraphQL vai por POST e diz write: false
  def call(method, path, query: {}, headers: {}, body: nil, content_type: nil, timeout: nil, write: nil) # rubocop:disable Metrics/ParameterLists
    method = method.to_s.upcase
    raise Error, 'invalid_method' unless METHODS.include?(method) || DAV_METHODS.include?(method)

    write = WRITE_METHODS.include?(method) if write.nil?
    raise Error, 'write_not_allowed' if write && !@connection.allow_write && !@connection.nextcloud?

    uri = build_uri(path, query)
    timeout = (timeout.presence || @connection.timeout_seconds).to_i.clamp(1, 30)
    request = build_request(method, uri, headers, body, content_type)
    response = perform(request, uri, timeout)
    return response unless response.status == 401 && @connection.auth_type == 'oauth2'

    # token vencido antes da hora: pega outro e tenta uma vez mais
    perform(build_request(method, uri, headers, body, content_type, fresh_token: true), uri, timeout)
  end

  # o endereço que aparece no registro, sem a chave quando ela vai no endereço
  def masked(url)
    param = @connection.settings['query_param'].presence
    return url.to_s unless @connection.auth_type == 'query' && param

    url.to_s.gsub(/([?&]#{Regexp.escape(param)}=)[^&]*/, '\1***')
  end

  private

  def base_uri
    @base_uri ||= URI.parse(@connection.base_url)
  end

  def build_uri(path, query)
    path = path.to_s.strip
    raise Error, 'invalid_path' if path.match?(%r{\A[a-z][a-z0-9+.-]*:|\A//|\\}i)

    path = "/#{path}" unless path.empty? || path.start_with?('/', '?')
    path_part, query_part = loose_escape(path).split('?', 2)
    full_path = normalize_path("#{base_uri.path}#{path_part}")
    raise Error, 'invalid_path' unless full_path.start_with?(base_uri.path.presence || '/')

    params = URI.decode_www_form(query_part.to_s.tr('+', ' ')) + query.to_h.map { |key, value| [key.to_s, value.to_s] }
    params << [@connection.settings['query_param'].presence || 'api_key', secret!('api_key')] if @connection.auth_type == 'query'
    uri = URI.parse("#{base_uri.scheme}://#{base_uri.host}:#{base_uri.port}#{full_path}")
    uri.query = URI.encode_www_form(params) if params.any?
    raise Error, 'invalid_path' unless uri.host == base_uri.host && uri.port == base_uri.port

    uri
  rescue URI::InvalidURIError, ArgumentError
    raise Error, 'invalid_path'
  end

  # o administrador pode ter escrito espaço ou acento no caminho: vira %XX (o que já está codificado fica)
  def loose_escape(path)
    path.gsub(%r{%(?![0-9A-Fa-f]{2})|[^A-Za-z0-9\-._~!$&'()*+,;=:@%/?]}) { |char| char.bytes.map { |byte| format('%%%02X', byte) }.join }
  end

  def normalize_path(path)
    parts = []
    path.split('/', -1).each do |part|
      next if part == '.'

      part == '..' ? parts.pop : parts << part
    end
    joined = parts.join('/')
    joined.start_with?('/') ? joined : "/#{joined}"
  end

  def build_request(method, uri, headers, body, content_type, fresh_token: false)
    request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri)
    request['Accept'] = 'application/json, application/xml;q=0.9, */*;q=0.8'
    request['User-Agent'] = USER_AGENT
    @connection.headers.to_h.each { |key, value| request[key] = value }
    headers.to_h.each { |key, value| request[key.to_s] = value.to_s if key.to_s.match?(Outsider::Bot::Connection::HEADER_NAME) }
    apply_auth(request, fresh_token)
    if body
      request.body = body.to_s
      request['Content-Type'] = content_type if content_type.present?
    end
    request
  end

  def apply_auth(request, fresh_token)
    settings = @connection.settings
    case @connection.auth_type
    when 'header' then request[settings['header_name'].presence || 'X-API-Key'] = secret!('api_key')
    when 'bearer' then request['Authorization'] = "Bearer #{secret!('token')}"
    when 'basic' then request.basic_auth(settings['username'].to_s, secret!('password'))
    when 'oauth2' then request['Authorization'] = "Bearer #{oauth_token(fresh: fresh_token)}"
    when 'headers'
      raise Error, 'missing_secret' if @connection.secret_headers.empty?

      @connection.secret_headers.each { |name, value| request[name] = value }
    end
  end

  def secret!(key)
    @connection.secret(key) || raise(Error, 'missing_secret')
  end

  def perform(request, uri, timeout, redirects = 0)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, body, content_type, location = transfer(request, uri, timeout, started)
    if redirect?(request, status, location, redirects)
      target = URI.join(uri.to_s, location)
      follow = build_request('GET', target, request.to_hash.transform_values(&:first).slice('accept'), nil, nil)
      return perform(follow, target, timeout, redirects + 1)
    end

    Response.new(status: status, body: body, content_type: content_type, url: masked(uri),
                 duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
  end

  def redirect?(request, status, location, redirects)
    return false unless [301, 302, 303, 307, 308].include?(status) && request.method == 'GET' && location.present?
    return false if redirects >= MAX_REDIRECTS

    target = URI.join(base_uri.to_s, location)
    target.host == base_uri.host && target.port == base_uri.port
  rescue URI::InvalidURIError, ArgumentError
    false
  end

  # rubocop:disable Metrics/MethodLength
  def transfer(request, uri, timeout, started)
    buffer = +''
    status = content_type = location = nil
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = http.write_timeout = http.ssl_timeout = timeout
    http.start do |connection|
      connection.request(request) do |response|
        status = response.code.to_i
        content_type = response['Content-Type'].to_s
        location = response['Location']
        response.read_body do |chunk|
          buffer << chunk
          raise Error, 'too_large' if buffer.bytesize > MAX_BODY
          raise Error, 'timeout' if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > timeout * 2
        end
      end
    end
    [status, decode(buffer, content_type), content_type, location]
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
    raise Error, 'timeout'
  rescue OpenSSL::SSL::SSLError => e
    raise Error.new('ssl_error', e.message)
  rescue *NETWORK_ERRORS => e
    raise Error.new('connection_failed', e.message)
  end
  # rubocop:enable Metrics/MethodLength

  def decode(body, content_type)
    charset = content_type[/charset="?([\w-]+)/i, 1]
    text = body.dup.force_encoding(Encoding.find(charset || 'UTF-8'))
    text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
  rescue ArgumentError, EncodingError
    body.dup.force_encoding('UTF-8').scrub('?')
  end

  # OAuth2 client credentials: o token fica no Redis, criptografado, até um minuto antes de vencer
  def oauth_token(fresh: false)
    key = format(OAUTH_KEY, id: @connection.id.to_i, version: @connection.updated_at.to_i)
    unless fresh
      cached = Outsider::Bot::Secrets.load(Redis::Alfred.get(key))&.dig('token')
      return cached if cached.present?
    end

    token, expires_in = request_oauth_token
    ttl = (expires_in.to_i.positive? ? expires_in.to_i - 60 : 3000).clamp(30, 86_400)
    Redis::Alfred.setex(key, Outsider::Bot::Secrets.dump('token' => token), ttl)
    token
  end

  def request_oauth_token
    settings = @connection.settings
    uri = URI.parse(settings['token_url'].to_s)
    raise Error, 'oauth_failed' unless uri.is_a?(URI::HTTP) && uri.host.present?

    form = { 'grant_type' => 'client_credentials', 'scope' => settings['scope'].presence }.compact
    request = Net::HTTP::Post.new(uri)
    if settings['client_auth'] == 'basic'
      request.basic_auth(settings['client_id'].to_s, secret!('client_secret'))
    else
      form['client_id'] = settings['client_id'].to_s
      form['client_secret'] = secret!('client_secret')
    end
    request.set_form_data(form)
    request['Accept'] = 'application/json'
    status, body, = transfer(request, uri, @connection.timeout_seconds.to_i.clamp(1, 30), Process.clock_gettime(Process::CLOCK_MONOTONIC))
    data = (JSON.parse(body) rescue {}) # rubocop:disable Style/RescueModifier
    raise Error.new('oauth_failed', "HTTP #{status}") unless status.between?(200, 299) && data['access_token'].present?

    [data['access_token'], data['expires_in']]
  rescue URI::InvalidURIError
    raise Error, 'oauth_failed'
  end
end
