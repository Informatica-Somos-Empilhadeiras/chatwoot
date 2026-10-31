# OUTSIDER: o que o bot manda na conversa. Toda mensagem do bot sai como mensagem enviada, sem agente
# (sender vazio), com content_attributes.outsider_bot para a bolha do painel mostrar o menu.
#
# Na caixa do WhatsApp pela Evolution, texto e menu saem direto pela Evolution, um depois do outro, para
# chegar ao cliente na ordem do fluxo (o texto que passa pelo webhook do Chatwoot chegava depois da
# lista). A Evolution grava cada um de volta na conversa (source_id WAID:<id>) e o Outsider::Bot::Echo
# faz essa cópia entrar como mensagem do bot. Se a Evolution falhar, o texto vai pelo Chatwoot.
#
# Menu, conforme a caixa:
#   - WhatsApp pela Evolution: lista (/message/sendList) ou botões (/message/sendButtons); se a
#     Evolution falhar, vai como texto numerado
#   - WhatsApp oficial e chat do site: menu do próprio Chatwoot (input_select)
#   - estilo texto e as outras caixas: texto com as opções numeradas
class Outsider::Bot::Sender
  include FileTypeHelper

  ECHO_WAIT = 6.seconds
  ECHO_INTERVAL = 0.4
  # "digitando..." antes de cada texto, como a Evolution faz com o que sai do Chatwoot
  TYPING_MS = 1200
  NUMBERS = %w[1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟].freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def text(content, extra = {})
    return if content.blank?

    attributes = { 'kind' => 'text' }.merge(extra)
    return evolution_text(content, attributes) if evolution?

    create_message(content: content, content_attributes: { 'outsider_bot' => attributes })
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

  # o próprio arquivo só vai pela Evolution; nas outras caixas o bot manda um link (Outsider::Bot::IntegrationSteps)
  def sends_files?
    evolution?
  end

  # documento do Nextcloud pelo WhatsApp: a Evolution baixa pelo url (link público temporário). Na conversa
  # fica só o nome com o link para abrir no Nextcloud: a cópia que a Evolution grava vem sem o arquivo
  # (Outsider::Bot::EchoBuilder), para não guardar o mesmo arquivo de novo no Chatwoot.
  def document(doc, url:, caption:, note_url:)
    attributes = { 'kind' => 'document', 'name' => doc['nome'].to_s }
    note = ["📄 *#{doc['nome']}*", caption.presence,
            note_url && "#{I18n.t('outsider_bot.documents.open_in_nextcloud')}: #{note_url}"].compact.join("\n")
    send_by_evolution(note, attributes) do
      evolution_api.send_media(number: recipient, mediatype: 'document', mimetype: doc['tipo'].presence || 'application/octet-stream',
                               file_name: doc['nome'].to_s, caption: caption.presence, media: url)
    end
  end

  # arquivo guardado no bloco Enviar arquivo: sai pela Evolution (ou pela própria caixa) e a mensagem da
  # conversa aponta para o mesmo arquivo do fluxo; a cópia que a Evolution grava vem sem o arquivo.
  def file(blob, caption:)
    attributes = { 'kind' => 'file', 'name' => blob.filename.to_s }
    return create_file_message(blob, caption, attributes) unless evolution?

    message = send_by_evolution(caption.to_s, attributes) do
      evolution_api.send_media(number: recipient, mediatype: evolution_media_type(blob.content_type),
                               mimetype: blob.content_type.presence || 'application/octet-stream', file_name: blob.filename.to_s,
                               caption: caption.presence, media: Base64.strict_encode64(blob.download))
    end
    attach_blob(message, blob)
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

  def evolution_text(content, attributes)
    send_by_evolution(content, attributes) { evolution_api.send_text(number: recipient, text: content, delay: TYPING_MS) }
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::Bot::Sender] texto pela Evolution falhou (#{e.code}), indo pelo Chatwoot")
    # a Evolution converte o markdown do Chatwoot de volta para o do WhatsApp
    create_message(content: chatwoot_markdown(content), content_attributes: { 'outsider_bot' => attributes })
  end

  def evolution_menu(data, options, style, attributes)
    send_by_evolution(numbered_text(data, options), attributes) do
      style == 'buttons' ? send_buttons(data, options) : send_list(data, options)
    end
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::Bot::Sender] menu pela Evolution falhou (#{e.code}), indo como texto")
    text(numbered_text(data, options), attributes.merge('style' => 'text'))
  end

  # o bloco chama a Evolution; content é o texto do WhatsApp, que fica na conversa no markdown do Chatwoot
  def send_by_evolution(content, attributes)
    content = chatwoot_markdown(content)
    source_id = Outsider::Bot::Echo.sending(@conversation) do
      response = yield
      message_id = response.dig('key', 'id') if response.is_a?(Hash)
      raise Outsider::EvolutionApi::Error, 'evolution_error' if message_id.blank?

      "WAID:#{message_id}".tap { |id| Outsider::Bot::Echo.remember(id, content: content, attributes: attributes) }
    end
    store_echo(source_id, content, attributes)
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

  # a Evolution grava na conversa o que saiu por ela (o Outsider::Bot::EchoBuilder já grava como mensagem
  # do bot); esperamos a cópia antes de seguir, para a conversa ficar na ordem. Se ela demorar, a
  # mensagem é criada aqui com o mesmo source_id, que a Evolution reconhece e não manda de novo ao
  # WhatsApp. A cópia que entrou como de agente (o id chegou tarde) é corrigida aqui.
  def store_echo(source_id, content, attributes)
    echo = wait_for_echo(source_id)
    bot = { 'outsider_bot' => attributes }
    return create_message(content: content, source_id: source_id, content_attributes: bot) unless echo
    return echo if echo.sender.nil? && echo.content_attributes.to_h['outsider_bot'].present?

    echo.tap { echo.update!(sender: nil, content: content, content_attributes: echo.content_attributes.to_h.merge(bot)) }
  end

  def wait_for_echo(source_id)
    deadline = ECHO_WAIT.from_now
    loop do
      message = Message.uncached { Message.find_by(inbox_id: @conversation.inbox_id, source_id: source_id) }
      return message if message || Time.current > deadline

      sleep ECHO_INTERVAL
    end
  end

  # *negrito*, _itálico_ e ~riscado~ do WhatsApp no markdown do Chatwoot, como a Evolution converte; os
  # endereços ficam como estão (um link com _ no meio não vira itálico)
  def chatwoot_markdown(text)
    text.to_s.split(%r{(https?://\S+)}).each_with_index.map do |part, index|
      next part if index.odd?

      part.gsub(/\*((?!\s)[^\n*]+?(?<!\s))\*/, '**\\1**')
          .gsub(/_((?!\s)[^\n_]+?(?<!\s))_/, '*\\1*')
          .gsub(/~((?!\s)[^\n~]+?(?<!\s))~/, '~~\\1~~')
    end.join
  end

  def evolution_media_type(content_type)
    case content_type
    when 'image/jpeg', 'image/png' then 'image'
    when 'video/mp4' then 'video'
    else 'document'
    end
  end

  def create_file_message(blob, caption, attributes)
    message = @conversation.messages.new(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
                                         sender: nil, content: caption.presence, content_attributes: { 'outsider_bot' => attributes })
    message.attachments.new(account_id: @conversation.account_id, file_type: file_type(blob.content_type), file: blob)
    message.save!
    message
  end

  # a mensagem já foi mostrada sem o arquivo: o updated_at avisa a tela de novo
  def attach_blob(message, blob)
    return message if ActiveStorage::Attachment.exists?(record_type: 'Attachment', record_id: message.attachments.select(:id), blob_id: blob.id)

    message.attachments.create!(account_id: message.account_id, file_type: file_type(blob.content_type), file: blob)
    message.update!(updated_at: Time.current)
    message
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
