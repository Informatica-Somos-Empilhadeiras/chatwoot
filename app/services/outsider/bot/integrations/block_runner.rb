# OUTSIDER: roda um bloco de integração do bot e diz por qual saída seguir. O mesmo código serve o motor
# (Outsider::Bot::Runner, na conversa) e o Testar do editor (com variáveis de exemplo).
#   api        -> ok | error         guarda a resposta em {{variável}}, o código HTTP em {{variável_status}}
#                                    e os campos escolhidos no teste em variáveis próprias
#   decision   -> regra | default
#   sheet      -> found | not_found  guarda a linha em {{variável}} ({{linha.coluna}})
#   doc_search -> found | not_found | error; achou vários e o cliente escolhe: choice (a lista)
#   db_query   -> found | not_found | error  guarda a primeira linha (ou a lista) em {{variável}} e quantas
#                                            linhas o comando mexeu em {{variável_linhas}}
# Toda chamada a outro sistema e toda busca em planilha entram no registro (Outsider::Bot::Log).
class Outsider::Bot::Integrations::BlockRunner
  Result = Struct.new(:port, :variables, :choice, :response, keyword_init: true)
  Http = Outsider::Bot::Integrations::Http
  MAX_VALUE = 64.kilobytes

  # context: { flow_id:, session_id:, conversation_id:, test: }
  def initialize(account:, template:, context: {})
    @account = account
    @template = template
    @context = context
  end

  def run(node)
    data = node['data'].to_h
    case node['type']
    when 'api' then api(node, data)
    when 'decision' then Result.new(port: Outsider::Bot::Integrations::Decision.new(@template).port(data), variables: {})
    when 'sheet' then sheet(node, data)
    when 'doc_search' then doc_search(node, data)
    when 'db_query' then db_query(node, data)
    else Result.new(port: 'error', variables: {})
    end
  end

  def find_connection(id, kind)
    Outsider::Bot::Connection.find_by(account_id: @account.id, id: id, kind: kind) if id.present?
  end

  def log(node, kind, status, connection: nil, response: nil, detail: {}, duration_ms: nil) # rubocop:disable Metrics/ParameterLists
    Outsider::Bot::Log.record(
      account_id: @account.id, flow_id: @context[:flow_id], session_id: @context[:session_id], conversation_id: @context[:conversation_id],
      connection_id: connection&.id, node_id: node['id'], kind: kind, status: status, http_status: response&.status,
      duration_ms: duration_ms || response&.duration_ms, detail: detail.merge('test' => @context[:test] || nil).compact
    )
  end

  # um valor grande demais não fica na conversa (o registro mostra o começo)
  def capped(value)
    case value
    when String then value.first(MAX_VALUE)
    when Hash, Array then value.to_json.bytesize <= MAX_VALUE ? value : nil
    else value
    end
  end

  private

  def api(node, data)
    connection = find_connection(data['connection_id'], 'http')
    return missing(node, 'api', data, 'no_connection', 'error') unless connection

    call = Outsider::Bot::Integrations::ApiCall.new(connection, @template)
    response = call.call(data)
    ok = response.success?
    log(node, 'api', ok ? 'ok' : 'error', connection: connection, response: response,
                                          detail: call.summary.merge('url' => response.url, 'cached' => response.cached || nil,
                                                                     'response' => Outsider::Bot::Log.excerpt(response.body),
                                                                     'error' => ok ? nil : "http_#{response.status}").compact)
    Result.new(port: ok ? 'ok' : 'error', variables: api_variables(data, response, ok ? '' : "http_#{response.status}"), response: response)
  rescue Http::Error => e
    log(node, 'api', 'error', connection: connection, detail: (call&.summary || {}).merge('error' => e.code, 'message' => e.message.first(300)))
    Result.new(port: 'error', variables: { 'erro' => e.code, "#{data['variable']}_status" => nil })
  end

  def api_variables(data, response, error)
    variable = data['variable'].presence || 'resultado'
    value = response.data.nil? ? response.body.to_s : response.data
    variables = { variable => capped(value), "#{variable}_status" => response.status, 'erro' => error }
    Array(data['mappings']).each do |mapping|
      next if mapping['variable'].blank?

      variables[mapping['variable']] = capped(Outsider::Bot::JsonPath.dig(response.data, mapping['path']))
    end
    variables
  end

  def sheet(node, data)
    dataset = Outsider::Bot::Dataset.find_by(account_id: @account.id, id: data['dataset_id'])
    return missing(node, 'sheet', data, 'no_dataset', 'not_found') unless dataset

    value = @template.render(data['value'])
    row = Outsider::Bot::Integrations::DatasetLookup.new(dataset).find(column: data['column'], operator: data['operator'], value: value)
    log(node, 'sheet', row ? 'ok' : 'not_found', detail: { 'dataset' => dataset.name, 'column' => data['column'], 'value' => value.first(200) })
    Result.new(port: row ? 'found' : 'not_found', variables: { (data['variable'].presence || 'linha') => row })
  end

  def doc_search(node, data)
    variable = data['variable'].presence || 'documento'
    connection = find_connection(data['connection_id'], 'nextcloud')
    return missing(node, 'doc_search', data, 'no_connection', 'error') unless connection
    # uma variável vazia (o cliente não respondeu) não pode virar "todos os documentos da pasta"
    if blank_variable?(data['query']) || blank_variable?(data['folder'])
      return missing(node, 'doc_search', data, 'empty_value', 'not_found', connection)
    end

    query = @template.render(data['query'])
    folder = @template.render(data['folder'], context: :segment)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    items = Outsider::Bot::Integrations::Nextcloud.new(connection).search(query: query, folder: folder, extensions: data['extensions'],
                                                                          limit: data['limit'])
    log_search(node, connection, items, started, query, folder)
    return Result.new(port: 'not_found', variables: { variable => nil }) if items.empty?
    return Result.new(port: 'found', variables: { variable => items.first }) if items.one? || data['pick'] == 'first'

    Result.new(port: 'found', variables: {}, choice: items)
  rescue Http::Error => e
    log(node, 'doc_search', 'error', connection: connection, detail: { 'query' => query, 'folder' => folder, 'error' => e.code,
                                                                       'message' => e.message.first(300) }.compact)
    Result.new(port: 'error', variables: { 'erro' => e.code })
  end

  def db_query(node, data)
    variable = data['variable'].presence || 'registro'
    connection = find_connection(data['connection_id'], 'postgres')
    return missing(node, 'db_query', data, 'no_connection', 'error') unless connection

    sql, params = @template.render_sql(data['sql'])
    result = Outsider::Bot::Integrations::Postgres.new(connection, read_only: @context[:read_only])
                                                  .query(sql, params, limit: data['mode'] == 'all' ? data['limit'] : 1)
    found = result.rows.any? || result.affected.positive?
    log(node, 'db_query', found ? 'ok' : 'not_found', connection: connection, duration_ms: result.duration_ms,
                                                      detail: { 'sql' => sql.first(500), 'params' => params.map { |value| value.to_s.first(100) },
                                                                'rows' => result.rows.size, 'affected' => result.affected,
                                                                'response' => Outsider::Bot::Log.excerpt(result.rows.first(3)) })
    value = data['mode'] == 'all' ? result.rows : result.rows.first
    Result.new(port: found ? 'found' : 'not_found', variables: { variable => capped(value), "#{variable}_linhas" => result.affected, 'erro' => '' })
  rescue Http::Error => e
    unless @context[:read_only] && e.code == 'write_not_allowed' # Testar: vai pedir confirmação, não é erro
      detail = { 'sql' => sql&.first(500), 'error' => e.code, 'message' => e.message.first(300) }.compact
      log(node, 'db_query', 'error', connection: connection, detail: detail)
    end
    Result.new(port: 'error', variables: { variable => nil, 'erro' => e.code })
  end

  def log_search(node, connection, items, started, query, folder)
    duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Outsider::Bot::Log.record(
      account_id: @account.id, flow_id: @context[:flow_id], session_id: @context[:session_id], conversation_id: @context[:conversation_id],
      connection_id: connection.id, node_id: node['id'], kind: 'doc_search', status: items.any? ? 'ok' : 'not_found', duration_ms: duration,
      detail: { 'query' => query, 'folder' => folder, 'found' => items.size, 'files' => items.pluck('nome').first(10),
                'test' => @context[:test] || nil }.compact
    )
  end

  def blank_variable?(text)
    text.to_s.scan(Outsider::Bot::Template::PATTERN).any? { |path, filters| @template.to_text(@template.value_of(path, filters)).strip.empty? }
  end

  def missing(node, kind, data, error, port, connection = nil)
    log(node, kind, port == 'not_found' ? 'not_found' : 'error', connection: connection, detail: { 'error' => error })
    variables = { 'erro' => error }
    variables[data['variable']] = nil if data['variable'].present? && kind != 'api'
    Result.new(port: port, variables: variables)
  end
end
