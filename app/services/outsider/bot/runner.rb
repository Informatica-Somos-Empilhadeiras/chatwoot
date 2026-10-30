# OUTSIDER: o motor do bot. Recebe a mensagem do cliente (Outsider::Bot::RunJob), acha a conversa no
# fluxo (Outsider::Bot::Session) ou começa um fluxo, e anda pelos blocos até um que espera resposta
# (menu, pergunta), um tempo (mensagem com espera) ou o fim.
#
# - roda só em conversa sem agente (a não ser que o bloco Início diga o contrário) e nunca em grupo
# - um agente que responde, assume ou resolve a conversa para o bot (Outsider::Bot::Listener)
# - enquanto o bot conversa, a conversa pode ficar Pendente (sai da aba Esperando); ao passar para a
#   equipe ou acabar sem resolver, volta a Aberta
# - no máximo MAX_STEPS blocos por mensagem, para um desenho com volta não rodar para sempre
class Outsider::Bot::Runner
  MAX_STEPS = 40
  VARIABLE = /\{\{\s*([a-z0-9_.]+)\s*\}\}/i

  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
  end

  def handle_incoming(message)
    return if skip?(message)

    with_account_locale { process(message) }
  end

  # depois da espera de um bloco Mensagem (Outsider::Bot::ContinueJob)
  def resume(session, node_id)
    return unless session.active? && session.node_id == node_id && session.waiting['type'] == 'delay'

    @session = session
    @graph = session.flow.graph_object
    with_account_locale { walk(node_id, delayed: node_id) }
  end

  def cancel(session, reopen: true)
    session.update!(status: :cancelled, waiting: {})
    reopen_conversation(session) if reopen
  end

  private

  attr_reader :session, :graph

  def with_account_locale(&)
    locale = @account.locale.presence&.to_sym
    I18n.available_locales.include?(locale) ? I18n.with_locale(locale, &) : yield
  end

  def process(message)
    session = active_session
    session = expire(session) if session&.expired_by_time?
    if session
      return cancel(session) if human_assigned?(session.flow)

      answer(session, message)
    else
      flow = pick_flow(message)
      start(flow, message) if flow
    end
  end

  def skip?(message)
    !message.incoming? || message.private? || @conversation.contact&.identifier.to_s.end_with?('@g.us') ||
      @conversation.resolved?
  end

  def active_session
    Outsider::Bot::Session.find_by(conversation_id: @conversation.id, status: :active)
  end

  def expire(session)
    session.update!(status: :expired, waiting: {})
    reopen_conversation(session)
    nil
  end

  def human_assigned?(flow)
    start = flow.graph_object.start
    @conversation.assignee_id.present? && start&.dig('data', 'only_unassigned') != false
  end

  # palavra-chave primeiro, depois conversa nova, depois "qualquer mensagem sem agente"
  def pick_flow(message)
    flows = Outsider::Bot::Flow.where(account_id: @account.id).active.order(:id).to_a
                               .select { |flow| flow.runs_in?(@conversation.inbox_id) && flow.graph_object.start }
    flows.find { |flow| trigger(flow) == 'keyword' && keyword?(flow, message) && allowed?(flow) } ||
      flows.find { |flow| trigger(flow) == 'new_conversation' && new_conversation?(message) && allowed?(flow) } ||
      flows.find { |flow| trigger(flow) == 'unassigned_message' && allowed?(flow) && rested?(flow) }
  end

  def trigger(flow)
    flow.graph_object.start.dig('data', 'trigger')
  end

  def allowed?(flow)
    !human_assigned?(flow)
  end

  def keyword?(flow, message)
    text = Outsider::Bot::ReplyMatcher.fold(message.content)
    words = Array(flow.graph_object.start.dig('data', 'keywords')).map { |word| Outsider::Bot::ReplyMatcher.fold(word) }.compact_blank
    words.any? { |word| text == word || " #{text} ".include?(" #{word} ") }
  end

  def new_conversation?(message)
    !@conversation.messages.where.not(message_type: :activity).where.not(id: message.id).exists?
  end

  # "qualquer mensagem": não repete antes de cooldown_hours desde a última vez, nem quando um agente
  # respondeu nesse tempo
  def rested?(flow)
    hours = flow.graph_object.start.dig('data', 'cooldown_hours').to_i
    since = hours.hours.ago
    return false if Outsider::Bot::Session.where(conversation_id: @conversation.id).exists?(['created_at > ?', since])

    !@conversation.messages.outgoing.where(sender_type: 'User', private: false).exists?(['created_at > ?', since])
  end

  def start(flow, message)
    @graph = flow.graph_object
    data = graph.start['data']
    @session = Outsider::Bot::Session.create!(account_id: @account.id, flow: flow, conversation: @conversation,
                                              node_id: graph.start['id'], variables: { 'primeira_mensagem' => message.content.to_s.first(500) })
    set_pending if data['set_pending']
    walk(graph.start['id'])
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def answer(session, message)
    @session = session
    @graph = session.flow.graph_object
    node = graph.node(session.node_id)
    return cancel(session) unless node

    case session.waiting['type']
    when 'menu' then answer_menu(node, message)
    when 'question' then answer_question(node, message)
    end
  end

  def answer_menu(node, message)
    data = node['data']
    option = Outsider::Bot::ReplyMatcher.new(data['options']).match(message.content)
    if option
      remember(node, option['label'])
      return walk_from(node, option['id'])
    end

    attempts = session.waiting['attempts'].to_i + 1
    return walk_from(node, 'invalid', fallback: :handoff) if attempts >= data['max_attempts'].to_i

    session.update!(waiting: session.waiting.merge('attempts' => attempts), expires_at: expires_at)
    sender.text(render(data['invalid_text'].presence || I18n.t('outsider_bot.invalid_option')))
    sender.menu(render_menu(data))
  end

  def answer_question(node, message)
    data = node['data']
    reply = message.content.to_s.strip.presence || I18n.t('outsider_bot.attachment_answer')
    remember(node, reply, variable: data['variable'])
    save_contact_field(data['contact_field'], reply)
    folded = Outsider::Bot::ReplyMatcher.fold(reply)
    route = Array(data['routes']).find do |item|
      Array(item['keywords']).any? { |word| (word = Outsider::Bot::ReplyMatcher.fold(word)).present? && " #{folded} ".include?(" #{word} ") }
    end
    walk_from(node, route ? route['id'] : 'default')
  end

  def walk_from(node, port, fallback: nil)
    following = graph.next_of(node, port)
    return walk(following['id']) if following
    return handoff({}) if fallback == :handoff

    finish(:finished)
  end

  # anda pelos blocos; delayed = bloco Mensagem cuja espera já passou
  def walk(node_id, delayed: nil)
    node = graph.node(node_id)
    MAX_STEPS.times do
      return finish(:finished) unless node

      node = step(node, delayed: delayed == node['id'])
      return if node == :stop
    end
    Rails.logger.warn("[Outsider::Bot::Runner] fluxo #{session.flow_id} passou de #{MAX_STEPS} blocos na conversa #{@conversation.id}")
    finish(:finished)
  end

  def step(node, delayed: false)
    data = node['data'] || {}
    case node['type']
    when 'start' then graph.next_of(node, 'next') || stop_with(:finished)
    when 'message' then message_step(node, data, delayed)
    when 'menu' then wait_for(node, 'menu') { sender.menu(render_menu(data)) }
    when 'question' then wait_for(node, 'question') { sender.text(render(data['text'])) }
    when 'condition' then graph.next_of(node, Outsider::Bot::Hours.new(data).open_now? ? 'inside' : 'outside') || stop_with(:finished)
    when 'action' then apply_action(data) && (graph.next_of(node, 'next') || stop_with(:finished))
    when 'handoff' then handoff(data) && :stop
    when 'end' then finish_end(data) && :stop
    else stop_with(:finished)
    end
  end

  def message_step(node, data, delayed)
    if data['delay_seconds'].to_i.positive? && !delayed
      session.update!(node_id: node['id'], waiting: { 'type' => 'delay' })
      Outsider::Bot::ContinueJob.set(wait: data['delay_seconds'].to_i.seconds).perform_later(session.id, node['id'])
      return :stop
    end
    sender.text(render(data['text']))
    graph.next_of(node, 'next') || stop_with(:finished)
  end

  def wait_for(node, type)
    yield
    session.update!(node_id: node['id'], waiting: { 'type' => type, 'attempts' => 0 }, expires_at: expires_at)
    :stop
  end

  def stop_with(status)
    finish(status)
    :stop
  end

  def expires_at
    minutes = graph.start&.dig('data', 'timeout_minutes').to_i
    minutes.positive? ? minutes.minutes.from_now : nil
  end

  def handoff(data)
    sender.text(render(data['text']))
    finish(:handed_off, reopen: false)
    @conversation.update!(team_id: data['team_id']) if data['team_id'] && @account.teams.exists?(id: data['team_id'])
    assign(data['assignee_id'])
    @conversation.update!(status: :open) unless @conversation.open?
    true
  end

  def finish_end(data)
    sender.text(render(data['text']))
    if data['resolve']
      finish(:finished, reopen: false)
      @conversation.update!(status: :resolved)
    else
      finish(:finished)
    end
    true
  end

  def finish(status, reopen: true)
    return unless session&.active?

    session.update!(status: status, waiting: {})
    reopen_conversation(session) if reopen
  end

  # a conversa que o bot deixou Pendente volta a Aberta para a equipe ver
  def reopen_conversation(bot_session)
    return unless bot_session.variables['_pending']

    conversation = Conversation.find_by(id: bot_session.conversation_id)
    conversation.update!(status: :open) if conversation&.pending?
  end

  def set_pending
    return unless @conversation.open? && @conversation.assignee_id.nil?

    @conversation.update!(status: :pending)
    session.update!(variables: session.variables.merge('_pending' => true))
  end

  def apply_action(data)
    @conversation.update!(team_id: data['team_id']) if data['team_id'] && @account.teams.exists?(id: data['team_id'])
    assign(data['assignee_id'])
    @conversation.add_labels(data['labels']) if data['labels'].present?
    @conversation.update!(priority: data['priority']) if data['priority'].present?
    sender.private_note(render(data['note'])) if data['note'].present?
    true
  end

  def assign(user_id)
    return if user_id.blank? || !@account.users.exists?(id: user_id)

    Conversations::AssignmentService.new(conversation: @conversation, assignee_id: user_id).perform
  end

  def remember(node, value, variable: nil)
    variables = session.variables.merge("bloco_#{node['id']}" => value.to_s.first(500))
    variables[variable] = value.to_s.first(500) if variable.present?
    session.update!(variables: variables)
  end

  def save_contact_field(field, value)
    contact = @conversation.contact
    return if field.blank? || contact.nil?

    value = value.to_s.squish.first(255)
    case field
    when 'name' then contact.update(name: value)
    when 'email' then contact.update(email: value.downcase) if value.match?(URI::MailTo::EMAIL_REGEXP)
    when 'company_name', 'city' then contact.update(additional_attributes: contact.additional_attributes.to_h.merge(field => value))
    end
  end

  def render_menu(data)
    data.merge('text' => render(data['text']), 'title' => render(data['title']), 'footer' => render(data['footer']))
  end

  # {{contato.nome}}, {{contato.primeiro_nome}}, {{contato.telefone}}, {{contato.email}} e as respostas guardadas
  def render(text)
    contact = @conversation.contact
    text.to_s.gsub(VARIABLE) do
      key = Regexp.last_match(1).downcase
      case key
      when 'contato.nome', 'nome_contato' then contact&.name.to_s
      when 'contato.primeiro_nome', 'primeiro_nome' then contact&.name.to_s.split.first.to_s
      when 'contato.telefone' then contact&.phone_number.to_s
      when 'contato.email' then contact&.email.to_s
      else session&.variables.to_h[key].to_s
      end
    end
  end

  def sender
    @sender ||= Outsider::Bot::Sender.new(@conversation)
  end
end
