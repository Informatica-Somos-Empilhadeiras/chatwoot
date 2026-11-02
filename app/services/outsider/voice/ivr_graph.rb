# OUTSIDER: o desenho de uma URA (Entrega 26): blocos (nodes) ligados por setas (edges), como o bot do WhatsApp
# (Outsider::Bot::Graph), com blocos próprios de telefone.
#
#   node = { 'id', 'type', 'x', 'y', 'data' }   edge = { 'id', 'from', 'port', 'to' }
#   prompt (o que a URA fala) = { 'text' => texto lido pela voz, 'audio_id' => áudio enviado (tem preferência) }
#
# Blocos e as saídas (ports) de cada um:
#   start      a ligação chega (voz usada para ler os textos)               -> next
#   say        fala uma mensagem                                            -> next
#   menu       "digite 1 para..., 2 para...": uma tecla por opção           -> uma saída por opção + invalid
#   collect    pede dígitos (CPF, pedido, protocolo) e guarda numa variável -> next / empty
#   hours      horário de atendimento                                       -> inside / outside
#   caller     quem está ligando: tem negócio aberto, é contato ou não      -> deal / contact / unknown
#   transfer   toca para os vendedores (regra padrão, dono do negócio, pessoas escolhidas, filial) ou um número
#              de fora                                                      -> no_answer
#   voicemail  grava um recado (fica na ligação, em Telefonia > Ligações)   -> next
#   hangup     fala (opcional) e desliga                                    -> (fim)
#
# sanitize limpa o que veio da tela: tipos e saídas conhecidos, textos com limite, ids seguros.
class Outsider::Voice::IvrGraph
  TYPES = %w[start say menu collect hours caller transfer voicemail hangup].freeze
  TARGETS = %w[default owner users branch number].freeze
  VOICES = %w[nova shimmer coral sage alloy ash echo fable onyx].freeze
  # "#" encerra a digitação no telefone: não serve de opção
  DIGITS = %w[1 2 3 4 5 6 7 8 9 0 *].freeze
  MAX_NODES = 150
  MAX_EDGES = 300
  MAX_OPTIONS = 12
  MAX_USERS = 30
  PROMPT_LIMIT = 1000
  ID = Outsider::Bot::Graph::ID

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

  def prompts
    @nodes.values.flat_map { |node| [node.dig('data', 'prompt'), node.dig('data', 'invalid_prompt')] }.compact
  end

  class << self
    def ports(node)
      data = node['data'] || {}
      case node['type']
      when 'start', 'say', 'voicemail' then ['next']
      when 'menu' then Array(data['options']).pluck('id') + ['invalid']
      when 'collect' then %w[next empty]
      when 'hours' then %w[inside outside]
      when 'caller' then %w[deal contact unknown]
      when 'transfer' then ['no_answer']
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
          'y' => node['y'].to_i.clamp(-20_000, 20_000), 'data' => send("clean_#{node['type']}", node['data'].to_h) }
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

    def clean_start(data)
      { 'voice' => VOICES.include?(data['voice']) ? data['voice'] : VOICES.first }
    end

    def clean_say(data)
      { 'prompt' => prompt(data['prompt']) }
    end

    def clean_menu(data)
      options = Array(data['options']).first(MAX_OPTIONS).filter_map do |option|
        option = option.to_h
        next unless option['id'].to_s.match?(ID) && DIGITS.include?(option['digit'].to_s)

        { 'id' => option['id'], 'digit' => option['digit'].to_s, 'label' => option['label'].to_s.squish.first(40) }
      end.uniq { |option| option['id'] }.uniq { |option| option['digit'] }
      { 'label' => data['label'].to_s.squish.first(40), 'prompt' => prompt(data['prompt']), 'options' => options,
        'invalid_prompt' => prompt(data['invalid_prompt']),
        'timeout' => int(data['timeout'], 5, 2, 15), 'max_attempts' => int(data['max_attempts'], 3, 1, 5) }
    end

    def clean_collect(data)
      min = int(data['min_digits'], 1, 1, 20)
      variable = data['variable'].to_s.downcase.gsub(/[^a-z0-9_]/, '_').first(30).presence || 'digitos'
      { 'prompt' => prompt(data['prompt']), 'invalid_prompt' => prompt(data['invalid_prompt']), 'variable' => variable,
        'label' => data['label'].to_s.squish.first(40), 'min_digits' => min, 'max_digits' => int(data['max_digits'], 11, min, 20),
        'timeout' => int(data['timeout'], 8, 3, 30), 'max_attempts' => int(data['max_attempts'], 2, 1, 5) }
    end

    # mesmo formato do bloco Horário de atendimento do bot (Outsider::Bot::Hours)
    def clean_hours(data)
      Outsider::Bot::Graph.clean_hours(data)
    end

    def clean_caller(_data)
      {}
    end

    def clean_transfer(data)
      {
        'prompt' => prompt(data['prompt']), 'target' => TARGETS.include?(data['target']) ? data['target'] : 'default',
        'user_ids' => Array(data['user_ids']).map(&:to_i).select(&:positive?).uniq.first(MAX_USERS),
        'branch_id' => data['branch_id'].to_s.first(20).presence, 'number' => data['number'].to_s.delete('^0-9').first(15),
        'ring_seconds' => int(data['ring_seconds'], 30, 10, 120)
      }
    end

    def clean_voicemail(data)
      { 'prompt' => prompt(data['prompt']), 'max_seconds' => int(data['max_seconds'], 120, 10, 300) }
    end

    def clean_hangup(data)
      { 'prompt' => prompt(data['prompt']) }
    end

    def prompt(value)
      value = value.to_h
      audio = value['audio_id'].to_s.match?(/\A\d+\z/) ? value['audio_id'].to_i : nil
      { 'text' => value['text'].to_s.squish.first(PROMPT_LIMIT), 'audio_id' => audio }
    end

    def int(value, default, min, max)
      value.to_s.match?(/\A-?\d+\z/) ? value.to_i.clamp(min, max) : default
    end
  end
end
