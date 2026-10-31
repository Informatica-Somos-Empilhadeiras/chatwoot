# OUTSIDER: os blocos de integração do fluxograma do bot (saídas e limpeza do que veio da tela). Entra no
# Outsider::Bot::Graph, que chama clean_<tipo> para cada bloco.
#   api        chama um sistema por uma conexão          -> ok / error
#   decision   segue conforme o valor de uma variável    -> uma saída por regra + default
#   sheet      procura uma linha numa planilha           -> found / not_found
#   doc_search procura documentos no Nextcloud           -> found / not_found / error
#   doc_send   manda o documento achado ao cliente       -> ok / error
#   db_query   consulta SQL num PostgreSQL               -> found / not_found / error
module Outsider::Bot::IntegrationGraph
  TYPES = %w[api decision sheet doc_search doc_send db_query].freeze
  METHODS = %w[GET POST PUT PATCH DELETE].freeze
  BODY_TYPES = %w[none json form xml text graphql].freeze
  DECISION_OPERATORS = %w[equals not_equals contains not_contains starts_with ends_with greater less empty not_empty].freeze
  SHEET_OPERATORS = %w[equals contains starts_with ends_with].freeze
  RESERVED_VARIABLES = %w[contato conversa erro link].freeze
  MAX_PAIRS = 20
  PATH = %r{\A[\p{L}\p{N}_.\[\]*:@$ /-]{1,200}\z}

  def integration_ports(type, data)
    case type
    when 'api', 'doc_send' then %w[ok error]
    when 'decision' then Array(data['rules']).pluck('id') + ['default']
    when 'sheet' then %w[found not_found]
    when 'doc_search', 'db_query' then %w[found not_found error]
    else []
    end
  end

  def clean_api(data)
    {
      'connection_id' => id_or_nil(data['connection_id']), 'method' => METHODS.include?(data['method']) ? data['method'] : 'GET',
      'path' => text(data['path'], 1000), 'query' => pairs(data['query']), 'headers' => pairs(data['headers']),
      'body_type' => BODY_TYPES.include?(data['body_type']) ? data['body_type'] : 'none', 'body' => text(data['body'], 20_000),
      'graphql_query' => text(data['graphql_query'], 20_000),
      'form' => pairs(data['form']), 'variable' => variable_name(data['variable'], 'resultado'), 'mappings' => mappings(data['mappings']),
      'cache_seconds' => int(data['cache_seconds'], 0, 0, 3600), 'timeout_seconds' => int(data['timeout_seconds'], 0, 0, 30)
    }
  end

  def clean_decision(data)
    rules = Array(data['rules']).first(Outsider::Bot::Graph::MAX_OPTIONS).filter_map do |rule|
      rule = rule.to_h
      next unless rule['id'].to_s.match?(Outsider::Bot::Graph::ID)

      { 'id' => rule['id'], 'label' => rule['label'].to_s.squish.first(40),
        'operator' => DECISION_OPERATORS.include?(rule['operator']) ? rule['operator'] : 'equals', 'value' => text(rule['value'], 500) }
    end
    { 'subject' => text(data['subject'], 500), 'rules' => rules.uniq { |rule| rule['id'] } }
  end

  def clean_sheet(data)
    {
      'dataset_id' => id_or_nil(data['dataset_id']), 'column' => data['column'].to_s.gsub(/[^a-z0-9_]/, '').first(60),
      'operator' => SHEET_OPERATORS.include?(data['operator']) ? data['operator'] : 'equals', 'value' => text(data['value'], 500),
      'variable' => variable_name(data['variable'], 'linha')
    }
  end

  def clean_doc_search(data)
    {
      'connection_id' => id_or_nil(data['connection_id']), 'folder' => text(data['folder'], 500), 'query' => text(data['query'], 500),
      'extensions' => words(data['extensions']).map { |ext| ext.downcase.delete('^a-z0-9') }.compact_blank.first(10),
      'limit' => int(data['limit'], 5, 1, 10), 'pick' => data['pick'] == 'first' ? 'first' : 'ask', 'text' => text(data['text'], 1000),
      'button_label' => data['button_label'].to_s.squish.first(20).presence || 'Ver documentos',
      'variable' => variable_name(data['variable'], 'documento'), 'max_attempts' => int(data['max_attempts'], 2, 1, 5)
    }
  end

  def clean_doc_send(data)
    {
      'source' => variable_name(data['source'], 'documento'), 'mode' => data['mode'] == 'link' ? 'link' : 'file',
      'caption' => text(data['caption'], 1000), 'link_text' => text(data['link_text'], 1000), 'link_days' => int(data['link_days'], 7, 1, 30)
    }
  end

  def clean_db_query(data)
    {
      'connection_id' => id_or_nil(data['connection_id']), 'sql' => text(data['sql'], 20_000), 'mode' => data['mode'] == 'all' ? 'all' : 'first',
      'limit' => int(data['limit'], 20, 1, 100), 'variable' => variable_name(data['variable'], 'registro')
    }
  end

  # [{ 'key', 'value' }] de parâmetros, cabeçalhos e campos de formulário
  def pairs(list)
    Array(list).first(MAX_PAIRS).filter_map do |item|
      item = item.to_h
      key = item['key'].to_s.strip.first(100)
      { 'key' => key, 'value' => item['value'].to_s.first(2000) } if key.present?
    end
  end

  # campos da resposta guardados em variáveis: [{ 'path' => 'dados.status', 'variable' => 'status_pedido' }]
  def mappings(list)
    Array(list).first(MAX_PAIRS).filter_map do |item|
      item = item.to_h
      path = item['path'].to_s.strip
      { 'path' => path, 'variable' => variable_name(item['variable'], 'campo') } if path.match?(PATH)
    end.uniq { |item| item['variable'] }
  end

  def variable_name(value, default)
    name = value.to_s.downcase.gsub(/[^a-z0-9_]/, '_').first(30).presence || default
    RESERVED_VARIABLES.include?(name) ? "#{name}_" : name
  end
end
