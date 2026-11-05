# OUTSIDER: a URA em andamento numa ligação (Entrega 26). A central pergunta o que fazer a cada passo, contando
# em que bloco estava (node), o que o cliente digitou (input) e como terminou a tentativa de tocar (dialstatus);
# a resposta é uma instrução em texto simples para o plano de discagem (lib/outsider/voice/dialplan.conf):
#
#   play|<sons>|<bloco>                                   fala e segue
#   menu|<sons>|<segundos>|<bloco>                        fala e espera 1 tecla
#   collect|<sons>|<máximo de dígitos>|<segundos>|<bloco> fala e espera os dígitos (# termina)
#   ring|<sons>|<segundos>|<bloco>|<etapa1>|<etapa2>...   fala e toca para os ramais, etapa por etapa
#   forward|<sons>|<segundos>|<bloco>|<bina>|<número>     fala e liga para um número de fora pela operadora
#   record|<sons>|<segundos>|<bloco>                      fala, bipa e grava o recado
#   hangup|<sons>                                         fala e desliga
#
# <sons> são os áudios dos blocos (Outsider::Voice::IvrPrompts) separados por "&", ou vazio. Os blocos de decisão
# (horário, quem está ligando) não falam: são resolvidos aqui mesmo. Por onde o cliente passou e o que digitou
# fica na ligação (ivr_data), para quem atende ver. Sem URA ou sem bloco de início, toca para todos como sem URA.
#
# O cliente não é derrubado por erro no desenho: saída sem bloco ligado, bloco apagado no meio da ligação ou laço
# (mais de MAX_STEPS passos) tocam para os vendedores pela regra de sempre (dead_end). Só desliga quem passou pelo
# bloco Encerrar, ou quem chegou ao fim do desenho depois de já ter tocado para alguém ou deixado recado.
class Outsider::Voice::IvrRunner
  MAX_STEPS = 60
  END_NODE = '_end'.freeze
  INPUT = /\A[0-9*]{1,20}\z/

  def initialize(settings, call)
    @settings = settings
    @call = call
    @flow = call.ivr_flow
    @graph = @flow&.graph_object
    @state = call.ivr_data.to_h.deep_dup
    @prompts = Outsider::Voice::IvrPrompts.new(settings.account)
  end

  def step(node_id:, input: nil, dialstatus: nil)
    return finish('hangup|') if node_id == END_NODE
    return finish(fallback) unless @graph&.start

    return finish(run(@graph.next_of(@graph.start, 'next'), false)) if node_id.blank?

    current = @graph.node(node_id.to_s)
    # o bloco saiu do desenho com a ligação em andamento
    return finish(dead_end) unless current

    finish(run(*resolve(current, input.to_s, dialstatus.to_s)))
  end

  private

  # a central fez o que o bloco pediu: para onde vai agora ([bloco, repetir com o aviso de opção inválida])
  def resolve(node, input, _dialstatus)
    case node['type']
    when 'menu' then resolve_menu(node, input)
    when 'collect' then resolve_collect(node, input)
    when 'transfer' then [@graph.next_of(node, 'no_answer'), false]
    when 'hangup' then [nil, false]
    else
      @state['voicemail'] = true if node['type'] == 'voicemail'
      [@graph.next_of(node, 'next'), false]
    end
  end

  def resolve_menu(node, input)
    data = node['data']
    option = Array(data['options']).find { |item| item['digit'] == input }
    return retry_or(node, 'invalid') unless option

    remember(data['label'].presence || I18n.t('outsider_voice.ivr.menu'), [option['digit'], option['label'].presence].compact.join(' - '))
    [@graph.next_of(node, option['id']), false]
  end

  def resolve_collect(node, input)
    data = node['data']
    return retry_or(node, 'empty') unless input.match?(INPUT) && input.length.between?(data['min_digits'], data['max_digits'])

    (@state['vars'] ||= {})[data['variable']] = input
    remember(data['label'].presence || data['variable'], input)
    [@graph.next_of(node, 'next'), false]
  end

  # opção inválida ou nada digitado: repete o bloco com o aviso até o limite de tentativas, depois sai pela saída
  def retry_or(node, port)
    attempts = (@state['attempts'] ||= {})
    attempts[node['id']] = attempts[node['id']].to_i + 1
    return [node, true] if attempts[node['id']] < node.dig('data', 'max_attempts').to_i

    attempts.delete(node['id'])
    [@graph.next_of(node, port), false]
  end

  def remember(title, answer)
    (@state['path'] ||= []) << { 'title' => title.to_s.first(40), 'answer' => answer.to_s.first(60) }
    @state['path'] = @state['path'].last(20)
  end

  # anda pelos blocos de decisão até um bloco que fala, toca ou grava
  def run(node, retry_prompt)
    loop do
      @state['steps'] = @state['steps'].to_i + 1
      return dead_end if node.nil? || @state['steps'] > MAX_STEPS

      case node['type']
      when 'hours' then node = @graph.next_of(node, Outsider::Bot::Hours.new(node['data']).open_now? ? 'inside' : 'outside')
      when 'caller' then node = @graph.next_of(node, caller_port)
      when 'start' then node = @graph.next_of(node, 'next')
      else
        instruction = instruction(node, retry_prompt)
        @state['rang'] = true if instruction && node['type'] == 'transfer'
        return instruction if instruction

        # transferência sem ninguém para tocar: segue como se ninguém tivesse atendido
        node = @graph.next_of(node, 'no_answer')
      end
      retry_prompt = false
    end
  end

  def caller_port
    return 'deal' if @call.opportunity&.open?

    @call.contact ? 'contact' : 'unknown'
  end

  def instruction(node, retry_prompt)
    data = node['data']
    id = node['id']
    case node['type']
    when 'say' then "play|#{sounds(data['prompt'])}|#{id}"
    when 'menu' then "menu|#{sounds(*([data['invalid_prompt']] if retry_prompt), data['prompt'])}|#{data['timeout']}|#{id}"
    when 'collect'
      "collect|#{sounds(*([data['invalid_prompt']] if retry_prompt), data['prompt'])}|#{data['max_digits']}|#{data['timeout']}|#{id}"
    when 'transfer' then transfer(node)
    when 'voicemail' then "record|#{sounds(data['prompt'])}|#{data['max_seconds']}|#{id}"
    when 'hangup' then "hangup|#{sounds(data['prompt'])}"
    end
  end

  def transfer(node)
    data = node['data']
    return forward(node) if data['target'] == 'number'

    steps = transfer_steps(data).reject(&:empty?)
    return if steps.empty?

    (["ring|#{sounds(data['prompt'])}|#{data['ring_seconds']}|#{node['id']}"] + steps).join('|')
  end

  def transfer_steps(data)
    agents = @settings.enabled_agents
    case data['target']
    when 'owner' then [Outsider::Voice::Router.targets([agents.dig(@call.opportunity&.owner_id, 'extension')].compact)]
    when 'users' then [Outsider::Voice::Router.targets(data['user_ids'].filter_map { |user_id| agents.dig(user_id, 'extension') })]
    when 'branch' then [Outsider::Voice::Router.targets(agents.values.select { |agent| agent['branch'] == data['branch_id'] }.pluck('extension'))]
    else router.ring_steps(@call.opportunity&.owner_id, @call.state_code)
    end
  end

  # para um número de fora, a ligação sai com o número que o cliente chamou (o da empresa)
  def forward(node)
    data = node['data']
    national = Outsider::Voice::PhoneNumber.national(data['number'])
    caller_id = Outsider::Voice::PhoneNumber.digits(@call.did)
    return unless national && caller_id.present? && @settings.trunk_ready?

    "forward|#{sounds(data['prompt'])}|#{data['ring_seconds']}|#{node['id']}|#{caller_id}|#{router.dial_string(national)}"
  end

  def sounds(*prompts)
    prompts.filter_map { |prompt| @prompts.sound(@flow, prompt) }.join('&')
  end

  def fallback
    @state['rang'] = true
    steps = router.ring_steps(@call.opportunity&.owner_id, @call.state_code)
    (["ring||#{@settings.data['ring_seconds']}|#{END_NODE}"] + steps).join('|')
  end

  # fim do desenho sem o bloco Encerrar: toca para os vendedores, a não ser que já tenha tocado ou o cliente tenha
  # deixado recado
  def dead_end
    @state['rang'] || @state['voicemail'] ? 'hangup|' : fallback
  end

  def router
    @router ||= Outsider::Voice::Router.new(@settings)
  end

  def finish(instruction)
    @call.update!(ivr_data: @state) if @state != @call.ivr_data
    instruction
  end
end
