# OUTSIDER: Gmail no bloco Google (Aplicativos). Espelho da caixa de e-mail da pessoa pela API do Gmail, com o login dela
# (permissão gmail.modify). Nada de e-mail fica gravado no Chatwoot: cada tela pede ao Google na hora, 25 por vez, e os
# detalhes de cada e-mail da lista vêm num pedido só (lote). Ficam só no cache (Redis): as não lidas da Principal por
# 1 minuto, para o número do menu, e onde está cada anexo do e-mail aberto (6 horas, o tempo do link assinado).
#
# Mesmo formato do Outlook (Outsider::Apps::Microsoft::Mail), para a tela ser uma só. As "pastas" são os marcadores do
# Gmail. A Principal é a Caixa de entrada sem Promoções, Social, Atualizações e Fóruns (como a aba do Gmail), e cada
# uma dessas aparece logo abaixo. "Todos os e-mails" faz o papel do Arquivo morto (arquivar = tirar da Caixa de entrada).
class Outsider::Apps::Google::Mail
  PAGE = 25
  MAX_LABELS = 40
  MAX_ATTACHMENTS = 20
  MAX_RECIPIENTS = 100
  MAX_SEND = 25.megabytes
  CATEGORIES = { 'CATEGORY_PROMOTIONS' => 'promotions', 'CATEGORY_SOCIAL' => 'social', 'CATEGORY_UPDATES' => 'updates',
                 'CATEGORY_FORUMS' => 'forums' }.freeze
  NOT_PRIMARY = '-category:promotions -category:social -category:updates -category:forums'.freeze
  SYSTEM = { 'DRAFT' => 'drafts', 'SENT' => 'sentitems', 'SPAM' => 'junkemail', 'TRASH' => 'deleteditems' }.freeze
  # nomes padrão das telas (o mesmo vocabulário do Outlook) para os marcadores do Gmail
  ALIASES = { 'inbox' => 'INBOX', 'drafts' => 'DRAFT', 'sentitems' => 'SENT', 'deleteditems' => 'TRASH', 'junkemail' => 'SPAM',
              'archive' => 'ALL' }.freeze
  ORDER = %w[inbox promotions social updates forums drafts sentitems archive junkemail deleteditems].freeze
  NAMES = {
    'pt' => { 'inbox' => 'Principal', 'promotions' => 'Promoções', 'social' => 'Social', 'updates' => 'Atualizações',
              'forums' => 'Fóruns', 'drafts' => 'Rascunhos', 'sentitems' => 'Enviados', 'archive' => 'Todos os e-mails',
              'junkemail' => 'Spam', 'deleteditems' => 'Lixeira' },
    'en' => { 'inbox' => 'Primary', 'promotions' => 'Promotions', 'social' => 'Social', 'updates' => 'Updates',
              'forums' => 'Forums', 'drafts' => 'Drafts', 'sentitems' => 'Sent', 'archive' => 'All mail', 'junkemail' => 'Spam',
              'deleteditems' => 'Trash' }
  }.freeze
  FILTERS = { 'unread' => 'is:unread', 'attachments' => 'has:attachment', 'flagged' => 'is:starred' }.freeze
  METADATA = %w[From To Subject Date].freeze

  def self.unread_key(link)
    "outsider:apps:google:unread:#{link.id}"
  end

  def initialize(link)
    @link = link
    @client = Outsider::Apps::Google::Client.new(link)
  end

  def folders
    labels = Array(@client.get("#{base}/labels")['labels'])
    mine = labels.select { |label| label['type'] == 'user' && label['labelListVisibility'] != 'labelHide' }.first(MAX_LABELS)
    ids = SYSTEM.keys + CATEGORIES.keys + mine.pluck('id')
    details = @client.batch(ids.map { |id| "/gmail/v1/users/me/labels/#{enc(id)}" }).compact.index_by { |label| label['id'] }
    list = [folder('INBOX', 'inbox', unread: unread_count)]
    CATEGORIES.each do |id, kind|
      list << folder(id, kind, total: details.dig(id, 'messagesTotal')) if details.dig(id, 'messagesTotal').to_i.positive?
    end
    SYSTEM.each do |id, kind|
      unread = kind == 'junkemail' ? details.dig(id, 'messagesUnread') : 0
      list << folder(id, kind, unread: unread, total: details.dig(id, 'messagesTotal'), movable: %w[DRAFT SENT].exclude?(id))
    end
    list << folder('ALL', 'archive')
    list.sort_by! { |item| ORDER.index(item[:kind]) || 99 }
    labels = mine.map do |label|
      { id: label['id'], name: label['name'].to_s, kind: 'label', unread: details.dig(label['id'], 'messagesUnread').to_i,
        total: details.dig(label['id'], 'messagesTotal').to_i, movable: true }
    end
    list + labels.sort_by { |item| item[:name].downcase }
  end

  # filter: 'unread' | 'attachments' | 'flagged' | nil; query: busca do Gmail; cursor: a "próxima página" (com a pasta,
  # o filtro e a busca dentro, porque a tela só manda o cursor)
  def messages(folder: 'INBOX', filter: nil, query: nil, cursor: nil)
    state = cursor.present? ? read_cursor(cursor) : { 'f' => folder_id(folder), 'x' => filter.to_s, 'q' => query.to_s.first(200) }
    data = @client.get("#{base}/messages", query: list_params(state).merge(pageToken: state['p'].presence))
    ids = Array(data['messages']).pluck('id')
    items = metadata(ids).compact.map { |item| summary(item) }
    { items: items, next: data['nextPageToken'].present? ? write_cursor(state.merge('p' => data['nextPageToken'])) : nil }
  end

  def message(id, mark_read: true)
    data = full(id)
    labels = Array(data['labelIds'])
    if mark_read && labels.include?('UNREAD') && labels.exclude?('DRAFT')
      @client.post("#{base}/messages/#{enc(id)}/modify", { removeLabelIds: ['UNREAD'] })
      data['labelIds'] = labels - ['UNREAD']
      forget_unread
    end
    parts = leaves(data['payload'])
    headers = header_map(data.dig('payload', 'headers'))
    attachments = attachment_list(id, parts)
    summary(data).merge(
      to: addresses(headers['to']), cc: addresses(headers['cc']), reply_to: addresses(headers['reply-to']),
      web_link: "https://mail.google.com/mail/?authuser=#{enc(@link.email)}#all/#{data['id']}",
      attachments: attachments.reject { |item| item[:inline] },
      html: Outsider::Apps::MailHtml.clean(body_html(parts), inline_images(attachments))
    )
  end

  # sinalizado = estrela do Gmail
  def update(id, read: nil, flagged: nil)
    add = []
    remove = []
    read.nil? || (read ? remove << 'UNREAD' : add << 'UNREAD')
    flagged.nil? || (flagged ? add << 'STARRED' : remove << 'STARRED')
    data = @client.post("#{base}/messages/#{enc(id)}/modify", { addLabelIds: add, removeLabelIds: remove })
    forget_unread
    { id: data['id'] || id, unread: Array(data['labelIds']).include?('UNREAD'), flagged: Array(data['labelIds']).include?('STARRED') }
  end

  # destination: id do marcador ou nome padrão. Lixeira = lixeira do Gmail (30 dias para recuperar); Todos os e-mails =
  # arquivar; um marcador da pessoa = "Mover para" do Gmail (põe o marcador e tira da Caixa de entrada).
  def move(id, destination)
    target = folder_id(destination)
    case target
    when 'TRASH' then @client.post("#{base}/messages/#{enc(id)}/trash", {})
    when 'ALL' then modify(id, remove: ['INBOX'])
    when 'SPAM' then modify(id, add: ['SPAM'], remove: ['INBOX'])
    when 'INBOX', *CATEGORIES.keys
      untrash_if_needed(id)
      category = target == 'INBOX' ? 'CATEGORY_PERSONAL' : target
      modify(id, add: ['INBOX', category], remove: ['SPAM'] + (CATEGORIES.keys - [category]))
    when 'SENT', 'DRAFT' then raise Outsider::Apps::Google::Client::Error.new('invalid', 422)
    else
      untrash_if_needed(id)
      modify(id, add: [target], remove: ['INBOX'])
    end
    forget_unread
  end

  # mode: 'new' | 'reply' | 'reply_all' | 'forward'. Monta o e-mail (MIME) e manda pelo Gmail da pessoa: fica nos Enviados
  # dela e, na resposta, na mesma conversa do Gmail. Encaminhar leva os anexos do original.
  def deliver(mode:, html:, subject: nil, to: [], cc: [], bcc: [], source_id: nil, files: [])
    source = mode == 'new' ? nil : full(source_id)
    headers = source ? header_map(source.dig('payload', 'headers')) : {}
    to, cc = reply_recipients(mode, headers, to, cc) if %w[reply reply_all].include?(mode)
    mail = build_mail(mode, html, source, headers, subject)
    mail.to = recipients(to) if recipients(to).any?
    mail.cc = recipients(cc) if recipients(cc).any?
    if recipients(bcc).any?
      mail.bcc = recipients(bcc)
      mail[:bcc].include_in_headers = true # o Gmail lê o Bcc do próprio e-mail e tira antes de mandar
    end
    Array(files).first(MAX_ATTACHMENTS).each do |file|
      file.rewind
      mail.attachments[clean_name(file.original_filename)] = { mime_type: file.content_type.presence || 'application/octet-stream',
                                                               content: file.read }
    end
    forward_attachments(mail, source) if mode == 'forward'
    send_raw(mail.encoded, mode.start_with?('reply') ? source['threadId'] : nil)
    true
  end

  # o anexo do e-mail (o Gmail entrega inteiro, em base64; até 25 MB): { name, content_type, body }
  def attachment(message_id, part_id)
    part = Rails.cache.read(part_key(message_id, part_id)) || find_part(message_id, part_id)
    raise Outsider::Apps::Google::Client::Error.new('not_found', 404) if part.nil?

    data = if part['a'].present?
             @client.get("#{base}/messages/#{enc(message_id)}/attachments/#{enc(part['a'])}")['data']
           else
             part['d']
           end
    { name: part['n'].presence || 'anexo', content_type: part['t'], body: decode64(data) }
  end

  # não lidas da Principal, para o número do menu (1 minuto no cache; acima de 99 o menu mostra 99+)
  def unread_count
    Rails.cache.fetch(self.class.unread_key(@link), expires_in: 1.minute) do
      data = @client.get("#{base}/messages", query: { labelIds: 'INBOX', q: "is:unread #{NOT_PRIMARY}", maxResults: 100,
                                                      fields: 'messages/id,nextPageToken' })
      data['nextPageToken'].present? ? 100 : Array(data['messages']).size
    end
  end

  def forget_unread
    Rails.cache.delete(self.class.unread_key(@link))
  end

  # resumo de vários e-mails num pedido só (observador e lista)
  def metadata(ids)
    query = { format: 'metadata', metadataHeaders: METADATA }
    @client.batch(ids.map { |id| "/gmail/v1/users/me/messages/#{enc(id)}?#{URI.encode_www_form(query)}" })
  end

  def summary(item)
    headers = header_map(item.dig('payload', 'headers'))
    labels = Array(item['labelIds'])
    {
      id: item['id'], subject: headers['subject'].to_s, preview: CGI.unescapeHTML(item['snippet'].to_s).first(200),
      from: addresses(headers['from']).first || addresses(headers['to']).first,
      date: item['internalDate'].present? ? Time.zone.at(item['internalDate'].to_i / 1000).utc.iso8601 : nil,
      unread: labels.include?('UNREAD'), flagged: labels.include?('STARRED'),
      has_attachments: attachments?(item['payload']), draft: labels.include?('DRAFT')
    }
  end

  # o e-mail chegou na Principal? (o observador não avisa de propaganda nem do que a própria pessoa mandou)
  def self.primary?(labels)
    labels = Array(labels)
    labels.include?('INBOX') && labels.include?('UNREAD') && !labels.intersect?(CATEGORIES.keys + %w[SENT DRAFT SPAM TRASH])
  end

  private

  def base
    Outsider::Apps::Google::Client::GMAIL
  end

  def enc(value)
    Outsider::Apps::Google::Client.enc(value)
  end

  def full(id)
    @current_id = id
    @client.get("#{base}/messages/#{enc(id)}", query: { format: 'full' })
  end

  def modify(id, add: [], remove: [])
    @client.post("#{base}/messages/#{enc(id)}/modify", { addLabelIds: add, removeLabelIds: remove })
  end

  def untrash_if_needed(id)
    labels = Array(@client.get("#{base}/messages/#{enc(id)}", query: { format: 'minimal', fields: 'labelIds' })['labelIds'])
    @client.post("#{base}/messages/#{enc(id)}/untrash", {}) if labels.include?('TRASH')
  end

  def folder(id, kind, unread: 0, total: 0, movable: true)
    names = NAMES[I18n.locale.to_s.start_with?('pt') ? 'pt' : 'en']
    { id: id, name: names[kind], kind: kind, unread: unread.to_i, total: total.to_i, movable: movable }
  end

  def folder_id(value)
    value = value.to_s
    ALIASES[value] || value.presence || 'INBOX'
  end

  def list_params(state)
    folder = state['f']
    # as abas (Promoções...) são a Caixa de entrada com "category:" na busca do Gmail
    label = CATEGORIES.key?(folder) ? 'INBOX' : folder
    scope = CATEGORIES.key?(folder) ? "category:#{CATEGORIES[folder]}" : (NOT_PRIMARY if folder == 'INBOX' && state['q'].blank?)
    search = [state['q'].presence, scope, FILTERS[state['x']]].compact
    params = { maxResults: PAGE, labelIds: (label == 'ALL' ? nil : label), q: search.join(' ').presence }
    params[:includeSpamTrash] = true if %w[SPAM TRASH].include?(folder)
    params
  end

  def write_cursor(state)
    Base64.urlsafe_encode64(state.to_json, padding: false)
  end

  def read_cursor(cursor)
    data = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
    raise ArgumentError unless data.is_a?(Hash)

    data.slice('f', 'x', 'q', 'p').transform_values(&:to_s)
  rescue ArgumentError, JSON::ParserError
    raise Outsider::Apps::Google::Client::Error.new('cursor', 422)
  end

  def header_map(headers)
    Array(headers).each_with_object({}) do |header, map|
      name = header['name'].to_s.downcase
      map[name] ||= decode_header(header['value'].to_s)
    end
  end

  def decode_header(value)
    value.include?('=?') ? ::Mail::Encodings.value_decode(value).to_s.scrub : value.scrub
  rescue StandardError
    value.scrub
  end

  def addresses(value)
    return [] if value.blank?

    ::Mail::AddressList.new(value).addresses.filter_map do |item|
      email = item.address.to_s
      name = decode_header(item.display_name.to_s).presence
      next if email.blank? && name.blank?

      { name: name || email, email: email }
    end
  rescue StandardError
    value.to_s.scan(/[\w.+'-]+@[\w-]+(?:\.[\w-]+)+/).map { |email| { name: email, email: email } }
  end

  def recipients(list)
    Array(list).map(&:to_s).map(&:strip).grep(URI::MailTo::EMAIL_REGEXP).uniq.first(MAX_RECIPIENTS)
  end

  # todas as partes "folha" do MIME (as que têm conteúdo), na ordem
  def leaves(payload, list = [])
    return list unless payload.is_a?(Hash)

    if payload['parts'].present?
      payload['parts'].each { |part| leaves(part, list) }
    else
      list << payload
    end
    list
  end

  def part_header(part, name)
    Array(part['headers']).find { |header| header['name'].to_s.casecmp(name).zero? }&.dig('value').to_s
  end

  def attachment_part?(part)
    part['filename'].present? || part_header(part, 'Content-Disposition').downcase.start_with?('attachment')
  end

  def attachments?(payload)
    return false unless payload.is_a?(Hash)
    return leaves(payload).any? { |part| attachment_part?(part) && !inline_part?(part) } if payload['parts'].present?

    payload['mimeType'] == 'multipart/mixed'
  end

  def inline_part?(part)
    part_header(part, 'Content-ID').present? && part['mimeType'].to_s.start_with?('image/') &&
      !part_header(part, 'Content-Disposition').downcase.start_with?('attachment')
  end

  def body_html(parts)
    html = parts.find { |part| part['mimeType'] == 'text/html' && !attachment_part?(part) }
    return text_of(html) if html

    plain = parts.find { |part| part['mimeType'] == 'text/plain' && !attachment_part?(part) }
    escaped = ERB::Util.html_escape(plain ? text_of(plain) : '').to_s
    "<div style=\"white-space:pre-wrap\">#{escaped}</div>"
  end

  # texto da parte em UTF-8 (o Gmail manda os bytes no charset do e-mail; e-mail antigo vem em ISO-8859-1/Windows-1252)
  def text_of(part)
    data = part.dig('body', 'data')
    if data.blank? && part.dig('body', 'attachmentId').present? && @current_id
      data = @client.get("#{base}/messages/#{enc(@current_id)}/attachments/#{enc(part.dig('body', 'attachmentId'))}")['data']
    end
    raw = decode64(data)
    utf = raw.dup.force_encoding('UTF-8')
    return utf if utf.valid_encoding?

    charset = part_header(part, 'Content-Type')[/charset="?([^";\s]+)/i, 1].presence || 'Windows-1252'
    raw.force_encoding(charset).encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
  rescue ArgumentError, EncodingError
    utf.to_s.scrub
  end

  def decode64(data)
    Base64.urlsafe_decode64(data.to_s)
  rescue ArgumentError
    ''
  end

  def attachment_list(id, parts)
    parts.select { |part| attachment_part?(part) || inline_part?(part) }.map do |part|
      name = part['filename'].presence || "anexo.#{Rack::Mime::MIME_TYPES.invert[part['mimeType']].to_s.delete('.').presence || 'bin'}"
      remember_part(id, part, name)
      { id: part['partId'], name: name, size: part.dig('body', 'size').to_i, content_type: part['mimeType'], inline: inline_part?(part),
        cid: part_header(part, 'Content-ID').delete('<>').strip,
        url: Outsider::Apps::FileToken.url(@link, kind: 'g_attachment', message_id: id, part_id: part['partId']) }
    end
  end

  # onde está o anexo (id do Google, nome e tipo), para o link assinado abrir sem buscar o e-mail inteiro de novo
  def remember_part(id, part, name)
    value = { 'a' => part.dig('body', 'attachmentId'), 'n' => name, 't' => part['mimeType'] }
    value['d'] = part.dig('body', 'data') if value['a'].blank? && part.dig('body', 'data').to_s.bytesize < 200_000
    Rails.cache.write(part_key(id, part['partId']), value, expires_in: Outsider::Apps::FileToken::EXPIRES)
  end

  def part_key(message_id, part_id)
    "outsider:apps:google:part:#{@link.id}:#{Digest::SHA256.hexdigest("#{message_id}|#{part_id}")}"
  end

  def find_part(message_id, part_id)
    part = leaves(full(message_id)['payload']).find { |item| item['partId'] == part_id.to_s }
    return nil if part.nil?

    { 'a' => part.dig('body', 'attachmentId'), 'd' => part.dig('body', 'data'), 'n' => part['filename'], 't' => part['mimeType'] }
  end

  # imagens coladas no corpo (src="cid:..."): casam pelo Content-ID e pelo nome
  def inline_images(attachments)
    attachments.select { |item| item[:content_type].to_s.start_with?('image/') }.each_with_object({}) do |item, map|
      map[item[:cid].split('@').first.downcase] = item[:url] if item[:cid].present?
      map[item[:name].to_s.downcase] ||= item[:url]
    end
  end

  # resposta: para quem mandou (ou o Reply-To); a todos: mais os outros destinatários, menos a própria pessoa
  def reply_recipients(mode, headers, extra_to, extra_cc)
    me = @link.email.to_s.downcase
    sender = addresses(headers['reply-to']).presence || addresses(headers['from'])
    to = sender.pluck(:email)
    cc = Array(extra_cc)
    if mode == 'reply_all'
      to += addresses(headers['to']).pluck(:email)
      cc += addresses(headers['cc']).pluck(:email)
    end
    to = (to + Array(extra_to)).reject { |email| email.to_s.downcase == me }.uniq
    to = sender.pluck(:email) if to.empty?
    [to, cc.reject { |email| email.to_s.downcase == me || to.include?(email) }.uniq]
  end

  def build_mail(mode, html, source, headers, subject)
    mail = ::Mail.new
    mail.charset = 'UTF-8'
    # multipart/mixed com o texto (simples e HTML) numa parte só e os anexos ao lado; o tipo vem antes das partes
    mail.content_type = 'multipart/mixed'
    from = ::Mail::Address.new(@link.email.to_s)
    from.display_name = @link.display_name if @link.display_name.present?
    mail.from = from.format
    mail.subject = (subject.presence || default_subject(mode, headers['subject'])).to_s.first(250)
    if source && mode.start_with?('reply') && headers['message-id'].present?
      mail.in_reply_to = headers['message-id']
      mail.references = "#{headers['references']} #{headers['message-id']}".strip
    end
    body = Outsider::Apps::MailHtml.outgoing(html)
    body += quote(mode, source, headers) if source
    alternative = ::Mail::Part.new
    alternative.content_type = 'multipart/alternative'
    alternative.add_part(text_part(body))
    alternative.add_part(html_part(body))
    mail.add_part(alternative)
    mail
  end

  def default_subject(mode, original)
    original = original.to_s
    return original if mode == 'new'
    return (original.match?(/\A(fwd?|enc):/i) ? original : "Fwd: #{original}") if mode == 'forward'

    original.match?(/\A(re|res):/i) ? original : "Re: #{original}"
  end

  # a mensagem original embaixo, como o Gmail faz (sem as imagens coladas, que eram partes do e-mail original)
  def quote(mode, source, headers)
    original = Nokogiri::HTML(body_html(leaves(source['payload'])).to_s.first(Outsider::Apps::MailHtml::MAX))
    original.css(Outsider::Apps::MailHtml::REMOVE).each(&:remove)
    original.css('img[src^="cid:"], img[src^="CID:"]').each(&:remove)
    inner = original.at('body')&.inner_html.to_s
    who = ERB::Util.html_escape(headers['from'].to_s)
    date = ERB::Util.html_escape(headers['date'].to_s)
    if mode == 'forward'
      info = [['De', headers['from']], ['Data', headers['date']], ['Assunto', headers['subject']], ['Para', headers['to']]]
             .map { |label, value| "#{label}: #{ERB::Util.html_escape(value.to_s)}" }.join('<br>')
      "<br><div class=\"gmail_quote\">---------- Mensagem encaminhada ---------<br>#{info}<br><br>#{inner}</div>"
    else
      "<br><div class=\"gmail_quote\"><div>Em #{date}, #{who} escreveu:</div>" \
        "<blockquote class=\"gmail_quote\" style=\"margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex\">#{inner}</blockquote></div>"
    end
  end

  def html_part(body)
    part = ::Mail::Part.new
    part.content_type = 'text/html; charset=UTF-8'
    part.body = body
    part
  end

  def text_part(body)
    part = ::Mail::Part.new
    part.content_type = 'text/plain; charset=UTF-8'
    part.body = Nokogiri::HTML(body.gsub(%r{<br\s*/?>}i, "\n")).text.strip
    part
  end

  def forward_attachments(mail, source)
    total = 0
    leaves(source['payload']).select { |part| attachment_part?(part) && !inline_part?(part) }.first(MAX_ATTACHMENTS).each do |part|
      size = part.dig('body', 'size').to_i
      raise Outsider::Apps::Google::Client::Error.new('too_big', 413) if total + size > MAX_SEND

      total += size
      data = part.dig('body', 'attachmentId').present? ? attachment(source['id'], part['partId'])[:body] : decode64(part.dig('body', 'data'))
      mail.attachments[clean_name(part['filename'])] = { mime_type: part['mimeType'].presence || 'application/octet-stream', content: data }
    end
  end

  def clean_name(name)
    name.to_s.tr('/\\:*?"<>|', '_').strip.first(200).presence || 'arquivo'
  end

  # envio pelo endereço de upload (aceita e-mail de até 35 MB); threadId deixa a resposta na mesma conversa
  def send_raw(raw, thread_id)
    raise Outsider::Apps::Google::Client::Error.new('too_big', 413) if raw.bytesize > 35.megabytes

    boundary = "outsider_#{SecureRandom.hex(10)}"
    meta = thread_id.present? ? { threadId: thread_id } : {}
    body = "--#{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n#{meta.to_json}\r\n" \
           "--#{boundary}\r\nContent-Type: message/rfc822\r\n\r\n#{raw}\r\n--#{boundary}--"
    url = "#{Outsider::Apps::Google::Client::GMAIL_UPLOAD}/messages/send"
    @client.raw(:post, url, body: body, content_type: "multipart/related; boundary=#{boundary}", query: { uploadType: 'multipart' })
  end
end
