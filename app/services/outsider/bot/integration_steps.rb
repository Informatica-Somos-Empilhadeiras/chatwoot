# OUTSIDER: os blocos de integração no motor do bot (incluído no Outsider::Bot::Runner). Cada bloco roda
# pelo Outsider::Bot::Integrations::BlockRunner, guarda as variáveis na conversa e segue pela saída.
#   - uma saída de falha sem seta (erro, não achou, nenhuma regra da Decisão) passa para a equipe, para o
#     cliente não ficar sem resposta
#   - no máximo MAX_CALLS chamadas a outros sistemas por mensagem do cliente
#   - Buscar documento que acha vários manda a lista para o cliente escolher (espera 'choice')
#   - Enviar documento manda o próprio arquivo pelo WhatsApp da Evolution (link público que vence amanhã e
#     é apagado logo depois do envio) ou, nas outras caixas e quando o arquivo não vai, um link com validade.
#     Na conversa fica o nome do arquivo com o link do Nextcloud, sem cópia do arquivo no Chatwoot.
module Outsider::Bot::IntegrationSteps
  FAILURE_PORTS = %w[error not_found default].freeze
  MAX_CALLS = 10
  MAX_FILE = 95.megabytes

  private

  def integration_step(node, data)
    return doc_send_step(node, data) if node['type'] == 'doc_send'
    return follow(node, 'error') if too_many_calls?(node)

    result = block_runner.run(node)
    store_variables(result.variables)
    return offer_choice(node, data, result.choice) if result.choice.present?

    follow(node, result.port)
  end

  def too_many_calls?(node)
    return false if node['type'] == 'decision'

    @integration_calls = @integration_calls.to_i + 1
    @integration_calls > MAX_CALLS
  end

  def follow(node, port)
    following = graph.next_of(node, port)
    return following if following
    return handoff({}) && :stop if FAILURE_PORTS.include?(port)

    stop_with(:finished)
  end

  def block_runner
    Outsider::Bot::Integrations::BlockRunner.new(
      account: @account, template: template,
      context: { flow_id: session.flow_id, session_id: session.id, conversation_id: @conversation.id }
    )
  end

  def template
    Outsider::Bot::Template.for_conversation(@conversation, session&.variables.to_h)
  end

  def store_variables(values)
    return if values.blank?

    session.update!(variables: session.variables.merge(values.transform_keys(&:to_s)))
  end

  # vários documentos: o cliente escolhe na lista (ou pelo número)
  def offer_choice(node, data, items)
    options = items.each_with_index.map do |item, index|
      { 'id' => "doc_#{index + 1}", 'label' => file_parts(item)[0].first(24).strip, 'description' => choice_description(item) }
    end
    menu = { 'text' => render(data['text'].presence || I18n.t('outsider_bot.documents.choose', count: items.size)),
             'title' => '', 'footer' => '', 'style' => 'list', 'button_label' => data['button_label'], 'options' => options }
    sender.menu(menu)
    session.update!(node_id: node['id'], expires_at: expires_at,
                    waiting: { 'type' => 'choice', 'attempts' => 0, 'options' => options, 'items' => items, 'menu' => menu })
    :stop
  end

  # na lista: o nome sem a extensão (até 24 letras); embaixo, o resto do nome, o tipo e a data
  def choice_description(item)
    base, extension = file_parts(item)
    date = Time.zone.parse(item['modificado'].to_s)&.in_time_zone(Outsider::Bot::Template::TIMEZONE)&.strftime('%d/%m/%Y') if item['modificado']
    rest = base.length > 24 ? base[24..].to_s.first(40).strip : nil
    [rest, extension&.upcase, date].compact_blank.join(' · ').first(72)
  end

  def file_parts(item)
    name = item['nome'].to_s
    extension = name[/\.([A-Za-z0-9]{1,5})\z/, 1]
    base = extension ? name.delete_suffix(".#{extension}") : name
    [base.presence || name, extension]
  end

  def answer_choice(node, message)
    waiting = session.waiting
    options = Array(waiting['options'])
    option = Outsider::Bot::ReplyMatcher.new(options).match(message.content)
    if option
      remember(node, option['label'])
      store_variables({ (node.dig('data', 'variable').presence || 'documento') => Array(waiting['items'])[options.index(option)] })
      return walk_from(node, 'found')
    end

    attempts = waiting['attempts'].to_i + 1
    return walk_from(node, 'not_found', fallback: :handoff) if attempts >= node.dig('data', 'max_attempts').to_i.clamp(1, 5)

    session.update!(waiting: waiting.merge('attempts' => attempts), expires_at: expires_at)
    sender.text(render(I18n.t('outsider_bot.invalid_option')))
    sender.menu(waiting['menu'])
  end

  def doc_send_step(node, data)
    doc = session.variables[data['source']]
    return doc_send_failed(node, nil, 'no_document') unless doc.is_a?(Hash) && doc['caminho'].present?

    connection = Outsider::Bot::Connection.find_by(account_id: @account.id, id: doc['conexao'], kind: 'nextcloud')
    return doc_send_failed(node, nil, 'no_connection') unless connection

    nextcloud = Outsider::Bot::Integrations::Nextcloud.new(connection)
    return doc_send_failed(node, connection, 'outside_root') unless nextcloud.inside_root?(doc['caminho'])

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    mode = send_document(nextcloud, doc, data)
    log_doc_send(node, connection, 'ok', started, 'file' => doc['nome'], 'mode' => mode)
    follow(node, 'ok')
  rescue Outsider::Bot::Integrations::Http::Error => e
    doc_send_failed(node, connection, e.code, e.message)
  end

  def send_document(nextcloud, doc, data)
    return 'file' if data['mode'] == 'file' && sender.sends_files? && doc['tamanho'].to_i <= MAX_FILE && send_file(nextcloud, doc, data)

    share = nextcloud.share_link(doc['caminho'], days: data['link_days'])
    text = data['link_text'].presence || I18n.t('outsider_bot.documents.link_text', days: data['link_days'])
    sender.text(template.with('link' => share['url']).render(text), 'kind' => 'document', 'name' => doc['nome'])
    'link'
  end

  def send_file(nextcloud, doc, data)
    share = nextcloud.share_link(doc['caminho'], days: 1)
    sender.document(doc, url: "#{share['url']}/download", caption: render(data['caption']), note_url: nextcloud.web_url(doc['id']))
    true
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::Bot::Runner] arquivo pela Evolution falhou (#{e.code}), indo como link")
    false
  ensure
    nextcloud.delete_share(share['id']) if share
  end

  def doc_send_failed(node, connection, code, message = nil)
    log_doc_send(node, connection, 'error', nil, 'error' => code, 'message' => message&.first(300))
    store_variables('erro' => code)
    follow(node, 'error')
  end

  def log_doc_send(node, connection, status, started, detail)
    duration = started && ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Outsider::Bot::Log.record(account_id: @account.id, flow_id: session.flow_id, session_id: session.id, conversation_id: @conversation.id,
                              connection_id: connection&.id, node_id: node['id'], kind: 'doc_send', status: status, duration_ms: duration,
                              detail: detail.compact)
  end
end
