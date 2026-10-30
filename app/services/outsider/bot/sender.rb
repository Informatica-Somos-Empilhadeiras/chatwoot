# OUTSIDER: o que o bot manda na conversa. Toda mensagem do bot sai como mensagem enviada, sem agente
# (sender vazio), com content_attributes.outsider_bot para a bolha do painel mostrar o menu.
#
# Menu, conforme a caixa:
#   - WhatsApp pela Evolution: lista (/message/sendList) ou botões (/message/sendButtons) direto na
#     Evolution, que registra a mensagem na conversa (source_id WAID:<id>, como o cartão de contato);
#     se a Evolution falhar, vai como texto numerado
#   - WhatsApp oficial e chat do site: menu do próprio Chatwoot (input_select)
#   - estilo texto e as outras caixas: texto com as opções numeradas
class Outsider::Bot::Sender
  ECHO_WAIT = 6.seconds
  ECHO_INTERVAL = 0.4
  NUMBERS = %w[1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟].freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def text(content, extra = {})
    return if content.blank?

    create_message(content: content, content_attributes: { 'outsider_bot' => { 'kind' => 'text' }.merge(extra) })
  end

  def private_note(content)
    return if content.blank?

    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id,
                                   message_type: :outgoing, private: true, content: content,
                                   content_attributes: { 'outsider_bot' => { 'kind' => 'note' } })
  end

  # data: bloco menu já com o texto preenchido (variáveis trocadas)
  def menu(data)
    options = Array(data['options'])
    style = effective_style(data['style'], options)
    attributes = { 'kind' => 'menu', 'style' => style, 'text' => data['text'].presence, 'title' => data['title'].presence,
                   'footer' => data['footer'].presence,
                   'button_label' => data['button_label'], 'options' => options.map { |option| option.slice('id', 'label', 'description') } }.compact

    return evolution_menu(data, options, style, attributes) if evolution? && style != 'text'
    return native_menu(data, options, attributes) if native_menu? && style != 'text'

    text(numbered_text(data, options), attributes.merge('style' => 'text'))
  end

  def numbered_text(data, options)
    lines = options.each_with_index.map do |option, index|
      "#{NUMBERS[index] || "#{index + 1}."} #{option['label']}#{" — #{option['description']}" if option['description'].present?}"
    end
    [heading(data), lines.join("\n"), data['footer'].presence].compact.join("\n\n")
  end

  private

  def heading(data)
    [data['title'].present? ? "*#{data['title']}*" : nil, data['text'].presence].compact.join("\n").presence
  end

  def effective_style(style, options)
    return 'text' if options.empty?
    return 'list' if style == 'buttons' && options.size > Outsider::Bot::Graph::MAX_BUTTONS

    style
  end

  def evolution?
    Outsider::EvolutionApi.evolution_inbox?(@conversation.inbox) && Outsider::EvolutionApi.configured?
  end

  def native_menu?
    @conversation.inbox.web_widget? || @conversation.inbox.whatsapp?
  end

  def evolution_menu(data, options, style, attributes)
    response = style == 'buttons' ? send_buttons(data, options) : send_list(data, options)
    message_id = response.dig('key', 'id')
    raise Outsider::EvolutionApi::Error, 'evolution_error' if message_id.blank?

    store_echo("WAID:#{message_id}", numbered_text(data, options), attributes)
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::Bot::Sender] menu pela Evolution falhou (#{e.code}), indo como texto")
    text(numbered_text(data, options), attributes.merge('style' => 'text'))
  end

  def send_list(data, options)
    evolution_api.send_list(
      number: recipient, title: data['title'].to_s, description: data['text'].presence || data['title'].presence || data['button_label'],
      footer_text: data['footer'].to_s, button_text: data['button_label'],
      sections: [{ title: data['title'].presence || data['button_label'],
                   rows: options.map { |option| list_row(option) } }]
    )
  end

  def list_row(option)
    { title: option['label'], description: option['description'].presence, rowId: option['id'] }.compact
  end

  def send_buttons(data, options)
    title = data['title'].presence || data['text']
    evolution_api.send_buttons(
      number: recipient, title: title, description: (data['title'].present? ? data['text'] : nil),
      footer: data['footer'].presence,
      buttons: options.map { |option| { type: 'reply', displayText: option['label'], id: option['id'] } }
    )
  end

  def native_menu(data, options, attributes)
    create_message(content: heading(data) || data['button_label'], content_type: 'input_select',
                   content_attributes: { 'items' => options.map { |option| { 'title' => option['label'], 'value' => option['id'] } },
                                         'outsider_bot' => attributes })
  end

  # a Evolution registra o que saiu por ela na conversa; esperamos para completar a mensagem (texto
  # legível e o menu para a bolha). Se ela demorar, a mensagem é criada aqui com o mesmo source_id,
  # que a Evolution reconhece e não manda de novo ao WhatsApp.
  def store_echo(source_id, content, attributes)
    echo = wait_for_echo(source_id)
    bot = { 'outsider_bot' => attributes }
    return echo.tap { echo.update!(content: content, content_attributes: echo.content_attributes.to_h.merge(bot)) } if echo

    create_message(content: content, source_id: source_id, content_attributes: bot)
  end

  def wait_for_echo(source_id)
    deadline = ECHO_WAIT.from_now
    loop do
      message = Message.uncached { Message.find_by(inbox_id: @conversation.inbox_id, source_id: source_id) }
      return message if message || Time.current > deadline

      sleep ECHO_INTERVAL
    end
  end

  def create_message(attributes)
    @conversation.messages.create!({ account_id: @conversation.account_id, inbox_id: @conversation.inbox_id,
                                     message_type: :outgoing, sender: nil }.merge(attributes))
  end

  def evolution_api
    @evolution_api ||= Outsider::EvolutionApi.new(@conversation.inbox)
  end

  # mesmo destino que a Evolution usa quando a mensagem sai do Chatwoot
  def recipient
    contact = @conversation.contact
    contact.identifier.presence || contact.phone_number.to_s.delete('^0-9')
  end
end
