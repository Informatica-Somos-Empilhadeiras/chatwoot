# OUTSIDER: o bloco API do bot. Monta a chamada com as variáveis da conversa (caminho, parâmetros,
# cabeçalhos e corpo JSON, formulário, XML, texto ou GraphQL) e chama a conexão
# (Outsider::Bot::Integrations::Http). Uma consulta (GET ou query do GraphQL) pode ficar guardada no Redis
# pelo tempo escolhido no bloco: a próxima igual responde na hora, sem chamar o outro sistema.
class Outsider::Bot::Integrations::ApiCall
  BODY_TYPES = %w[none json form xml text graphql].freeze
  CONTENT_TYPES = { 'json' => 'application/json', 'form' => 'application/x-www-form-urlencoded',
                    'xml' => 'application/xml; charset=utf-8', 'text' => 'text/plain; charset=utf-8', 'graphql' => 'application/json' }.freeze
  MUTATION = /(\A|\})\s*(mutation|subscription)\b/
  CACHE_KEY = 'OUTSIDER::BOT::CACHE::%<digest>s'.freeze
  CACHE_MAX = 256.kilobytes
  Http = Outsider::Bot::Integrations::Http

  # o que foi pedido, para o registro: { 'method', 'path', 'body' }
  attr_reader :summary

  def initialize(connection, template)
    @connection = connection
    @template = template
    @http = Http.new(connection)
  end

  def call(data)
    method = Http::METHODS.include?(data['method']) ? data['method'] : 'GET'
    method = 'POST' if data['body_type'] == 'graphql'
    path = @template.render(data['path'], context: :url)
    query = pairs(data['query']).to_h.transform_values { |value| @template.render(value) }
    headers = pairs(data['headers']).to_h.transform_values { |value| @template.render(value, context: :header) }
    @summary = { 'method' => method, 'path' => path }
    body, content_type = body_for(method, data)
    @summary['body'] = Outsider::Bot::Log.excerpt(body)
    timeout = data['timeout_seconds'].to_i.positive? ? data['timeout_seconds'].to_i : nil
    write = data['body_type'] == 'graphql' ? self.class.graphql_write?(data['graphql_query']) : nil
    cacheable = method == 'GET' || write == false
    cached(cacheable, data['cache_seconds'].to_i, [method, path, query, headers, body]) do
      @http.call(method, path, query: query, headers: headers, body: body, content_type: content_type, timeout: timeout, write: write)
    end
  end

  # consulta (query) só lê; mutation e subscription precisam de "permite alterar dados"
  def self.graphql_write?(query)
    query.to_s.gsub(/#[^\n]*/, '').match?(MUTATION)
  end

  private

  def pairs(list)
    Array(list).filter_map do |item|
      item = item.to_h
      key = item['key'].to_s.strip
      [key, item['value'].to_s] if key.present?
    end
  end

  def body_for(method, data)
    type = data['body_type'].to_s
    return [nil, nil] if method == 'GET' || type.blank? || type == 'none'

    body = case type
           when 'json' then json_body(data['body'])
           when 'graphql' then graphql_body(data)
           when 'form' then URI.encode_www_form(pairs(data['form']).map { |key, value| [key, @template.render(value)] })
           when 'xml' then @template.render(data['body'], context: :xml)
           else @template.render(data['body'])
           end
    [body, CONTENT_TYPES[type]]
  end

  # confere o JSON antes de mandar: um erro no corpo aparece no teste e no registro, sem chamar o sistema
  def json_body(source)
    body = @template.render(source, context: :json)
    JSON.parse(body) if body.strip.present?
    body
  rescue JSON::ParserError => e
    raise Http::Error.new('invalid_body', e.message.first(200))
  end

  # GraphQL: a consulta e as variáveis vão num JSON; dentro de aspas o valor entra escapado, como no JSON
  def graphql_body(data)
    query = @template.render(data['graphql_query'], context: :json)
    variables = data['body'].to_s.strip.present? ? JSON.parse(json_body(data['body'])) : {}
    { query: query, variables: variables }.to_json
  end

  # GET e consulta GraphQL podem ficar guardados; o que altera dados nunca
  def cached(cacheable, seconds, parts)
    return yield unless cacheable && seconds.positive?

    key = format(CACHE_KEY, digest: Digest::SHA256.hexdigest([@connection.id, @connection.updated_at.to_i, parts].to_json))
    hit = Redis::Alfred.get(key)
    return from_cache(hit) if hit

    response = yield
    if response.success? && response.body.to_s.bytesize <= CACHE_MAX
      Redis::Alfred.setex(key, response.to_h.slice(:status, :body, :content_type, :url).to_json, seconds.clamp(1, 3600))
    end
    response
  end

  def from_cache(hit)
    data = JSON.parse(hit)
    Http::Response.new(status: data['status'], body: data['body'], content_type: data['content_type'], url: data['url'],
                       duration_ms: 0, cached: true)
  end
end
