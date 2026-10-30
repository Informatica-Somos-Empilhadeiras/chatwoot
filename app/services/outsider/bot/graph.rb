# OUTSIDER: o desenho de um fluxo do bot: blocos (nodes) ligados por setas (edges).
#
#   node = { 'id', 'type', 'x', 'y', 'data' }   edge = { 'id', 'from', 'port', 'to' }
#
# Blocos e as saídas (ports) de cada um:
#   start      gatilho do fluxo                                   -> next
#   message    mensagem (com espera opcional, "digitando")        -> next
#   menu       pergunta com opções: lista, botões ou texto        -> uma saída por opção + invalid
#   question   texto livre (chatbot): guarda a resposta e segue
#              pela palavra-chave que aparecer na resposta        -> uma saída por regra + default
#   condition  horário de atendimento                             -> inside / outside
#   action     equipe, agente, etiquetas, prioridade, nota        -> next
#   handoff    passa para a equipe (a conversa fica aberta)       -> (fim)
#   end        encerra (pode resolver a conversa)                 -> (fim)
#
# sanitize limpa o que veio da tela: tipos e saídas conhecidos, textos com limite, ids seguros.
class Outsider::Bot::Graph
  TYPES = %w[start message menu question condition action handoff end].freeze
  STYLES = %w[list buttons text].freeze
  TRIGGERS = %w[unassigned_message new_conversation keyword].freeze
  CONTACT_FIELDS = ['', 'name', 'email', 'company_name', 'city'].freeze
  PRIORITIES = [nil, 'low', 'medium', 'high', 'urgent'].freeze
  MAX_NODES = 200
  MAX_EDGES = 400
  MAX_OPTIONS = 10
  MAX_BUTTONS = 3
  TEXT_LIMIT = 4096
  ID = /\A[A-Za-z0-9_-]{1,40}\z/
  TIME = /\A([01]\d|2[0-3]):[0-5]\d\z/
  DEFAULT_TIMEZONE = 'America/Sao_Paulo'.freeze
  DEFAULT_HOURS = (0..6).to_h do |day|
    [day.to_s, { 'enabled' => day.between?(1, 5), 'start' => '08:00', 'end' => '18:00' }]
  end.freeze

  attr_reader :nodes, :edges

  def initialize(graph)
    graph = graph.to_h.stringify_keys
    @nodes = Array(graph['nodes']).index_by { |node| node['id'] }
    @edges = Array(graph['edges'])
  end

  def start
    @nodes.values.find { |node| node['type'] == 'start' }
  end

  def node(id)
    @nodes[id]
  end

  def next_of(node, port)
    edge = @edges.find { |item| item['from'] == node['id'] && item['port'] == port }
    edge && @nodes[edge['to']]
  end

  class << self
    def ports(node)
      data = node['data'] || {}
      case node['type']
      when 'start', 'message', 'action' then ['next']
      when 'menu' then Array(data['options']).pluck('id') + ['invalid']
      when 'question' then Array(data['routes']).pluck('id') + ['default']
      when 'condition' then %w[inside outside]
      else []
      end
    end

    def sanitize(graph)
      graph = graph.to_h.deep_stringify_keys
      nodes = clean_nodes(Array(graph['nodes']))
      { 'nodes' => nodes, 'edges' => clean_edges(Array(graph['edges']), nodes) }
    end

    private

    def clean_nodes(list)
      seen_start = false
      list.first(MAX_NODES).filter_map do |node|
        node = node.to_h
        next unless TYPES.include?(node['type']) && node['id'].to_s.match?(ID)
        next if node['type'] == 'start' && seen_start

        seen_start ||= node['type'] == 'start'
        { 'id' => node['id'], 'type' => node['type'], 'x' => node['x'].to_i.clamp(-20_000, 20_000),
          'y' => node['y'].to_i.clamp(-20_000, 20_000), 'data' => clean_data(node['type'], node['data'].to_h) }
      end.uniq { |node| node['id'] }
    end

    def clean_edges(list, nodes)
      by_id = nodes.index_by { |node| node['id'] }
      list.first(MAX_EDGES).filter_map do |edge|
        edge = edge.to_h
        from = by_id[edge['from']]
        next unless from && by_id[edge['to']] && edge['from'] != edge['to'] && ports(from).include?(edge['port'])

        { 'id' => edge['id'].to_s.match?(ID) ? edge['id'] : SecureRandom.hex(6), 'from' => edge['from'], 'port' => edge['port'], 'to' => edge['to'] }
      end.uniq { |edge| [edge['from'], edge['port']] }
    end

    def clean_data(type, data)
      send("clean_#{type}", data)
    end

    def clean_start(data)
      {
        'trigger' => TRIGGERS.include?(data['trigger']) ? data['trigger'] : 'unassigned_message',
        'keywords' => words(data['keywords']),
        'cooldown_hours' => int(data['cooldown_hours'], 12, 0, 720),
        'timeout_minutes' => int(data['timeout_minutes'], 60, 5, 1440),
        'set_pending' => data.key?('set_pending') ? bool(data['set_pending']) : true,
        'only_unassigned' => data.key?('only_unassigned') ? bool(data['only_unassigned']) : true
      }
    end

    def clean_message(data)
      { 'text' => text(data['text']), 'delay_seconds' => int(data['delay_seconds'], 0, 0, 30) }
    end

    def clean_menu(data)
      style = STYLES.include?(data['style']) ? data['style'] : 'list'
      options = Array(data['options']).first(MAX_OPTIONS).filter_map do |option|
        option = option.to_h
        label = option['label'].to_s.squish.first(24)
        next if label.blank? || !option['id'].to_s.match?(ID)

        { 'id' => option['id'], 'label' => label, 'description' => option['description'].to_s.squish.first(72) }
      end.uniq { |option| option['id'] }
      {
        'text' => text(data['text']), 'title' => data['title'].to_s.squish.first(60),
        'footer' => data['footer'].to_s.squish.first(60), 'style' => style,
        'button_label' => data['button_label'].to_s.squish.first(20).presence || 'Ver opções',
        'options' => options, 'invalid_text' => text(data['invalid_text'], 1000),
        'max_attempts' => int(data['max_attempts'], 2, 1, 5)
      }
    end

    def clean_question(data)
      routes = Array(data['routes']).first(MAX_OPTIONS).filter_map do |route|
        route = route.to_h
        next unless route['id'].to_s.match?(ID)

        { 'id' => route['id'], 'label' => route['label'].to_s.squish.first(40), 'keywords' => words(route['keywords']) }
      end.uniq { |route| route['id'] }
      variable = data['variable'].to_s.downcase.gsub(/[^a-z0-9_]/, '_').first(30).presence || 'resposta'
      {
        'text' => text(data['text']), 'variable' => variable, 'routes' => routes,
        'contact_field' => CONTACT_FIELDS.include?(data['contact_field'].to_s) ? data['contact_field'].to_s : ''
      }
    end

    def clean_condition(data)
      hours = DEFAULT_HOURS.to_h do |day, default|
        given = data.dig('hours', day).to_h
        start = given['start'].to_s.match?(TIME) ? given['start'] : default['start']
        finish = given['end'].to_s.match?(TIME) ? given['end'] : default['end']
        [day, { 'enabled' => given.key?('enabled') ? bool(given['enabled']) : default['enabled'], 'start' => start, 'end' => finish }]
      end
      zone = ActiveSupport::TimeZone[data['timezone'].to_s] ? data['timezone'].to_s : DEFAULT_TIMEZONE
      { 'hours' => hours, 'timezone' => zone }
    end

    def clean_action(data)
      {
        'team_id' => id_or_nil(data['team_id']), 'assignee_id' => id_or_nil(data['assignee_id']),
        'labels' => words(data['labels']).map { |label| label.parameterize(separator: '_') }.compact_blank.uniq,
        'priority' => PRIORITIES.include?(data['priority'].presence) ? data['priority'].presence : nil,
        'note' => text(data['note'], 2000)
      }
    end

    def clean_handoff(data)
      { 'text' => text(data['text']), 'team_id' => id_or_nil(data['team_id']), 'assignee_id' => id_or_nil(data['assignee_id']) }
    end

    def clean_end(data)
      { 'text' => text(data['text']), 'resolve' => bool(data['resolve']) }
    end

    def text(value, limit = TEXT_LIMIT)
      value.to_s.strip.first(limit)
    end

    def words(value)
      list = value.is_a?(Array) ? value : value.to_s.split(/[,;\n]/)
      list.map { |word| word.to_s.squish.first(40) }.compact_blank.uniq.first(20)
    end

    def int(value, default, min, max)
      value.to_s.match?(/\A-?\d+\z/) ? value.to_i.clamp(min, max) : default
    end

    def bool(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def id_or_nil(value)
      value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
    end
  end
end
