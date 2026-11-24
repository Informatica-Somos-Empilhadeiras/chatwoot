# OUTSIDER: Outlook no bloco Microsoft (Aplicativos). Espelho da caixa de e-mail da pessoa pelo Microsoft Graph, com o login
# do "Conectar meu Teams" (permissões Mail.ReadWrite e Mail.Send, versão 4). Nada de e-mail fica gravado no Chatwoot: cada
# tela pede à Microsoft na hora, 25 por vez. Só o número de não lidas da Caixa de entrada fica 1 minuto no cache (Redis),
# para o número do menu, e os ids das pastas padrão ficam 1 dia.
#
# Tudo sai no formato comum dos aplicativos (o Gmail usa o mesmo), para a tela ser uma só:
#   folder:  { id, name, kind, unread, total }
#   summary: { id, subject, from: { name, email }, preview, date, unread, flagged, has_attachments, draft }
#   message: summary + { to, cc, html, web_link, attachments: [{ id, name, size, content_type, inline, url }] }
class Outsider::Apps::Microsoft::Mail
  PAGE = 25
  WELL_KNOWN = %w[inbox drafts sentitems deleteditems archive junkemail].freeze
  SMALL_ATTACHMENT = 3.megabytes
  UPLOAD_CHUNK = 320.kilobytes * 10
  MAX_ATTACHMENTS = 20
  MAX_RECIPIENTS = 100
  SUMMARY_FIELDS = 'id,subject,from,receivedDateTime,sentDateTime,isRead,hasAttachments,bodyPreview,flag,isDraft,toRecipients'.freeze
  MESSAGE_FIELDS = "#{SUMMARY_FIELDS},ccRecipients,bccRecipients,body,webLink,conversationId,replyTo".freeze

  def self.unread_key(link)
    "outsider:apps:microsoft:unread:#{link.id}"
  end

  def initialize(link)
    @link = link
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  # pastas padrão primeiro (Caixa de entrada, Rascunhos, Enviados, Excluídos, Arquivo morto, Lixo eletrônico), depois as
  # da pessoa em ordem alfabética
  def folders
    known = well_known_ids
    data = @client.get("/me/mailFolders?#{{ '$top' => 100, '$select' => 'id,displayName,unreadItemCount,totalItemCount' }.to_query}")
    list = Array(data['value']).map do |folder|
      kind = known.key(folder['id'])
      { id: folder['id'], name: folder['displayName'], kind: kind || 'custom', unread: folder['unreadItemCount'].to_i,
        total: folder['totalItemCount'].to_i }
    end
    list.sort_by { |folder| [WELL_KNOWN.index(folder[:kind]) || 99, folder[:name].to_s.downcase] }
  end

  # filter: 'unread' | 'attachments' | 'flagged' | nil; query: busca da Microsoft; cursor: o "próxima página" da Microsoft
  def messages(folder: 'inbox', filter: nil, query: nil, cursor: nil)
    data = @client.get(cursor.present? ? next_path(cursor) : list_path(folder, filter, query))
    { items: Array(data['value']).map { |item| summary(item) }, next: data['@odata.nextLink'].presence }
  end

  def message(id, mark_read: true)
    data = @client.get("/me/messages/#{enc(id)}?$select=#{MESSAGE_FIELDS}", headers: { 'Prefer' => 'outlook.body-content-type="html"' })
    if mark_read && data['isRead'] == false && data['isDraft'] != true
      @client.patch("/me/messages/#{enc(id)}", { isRead: true })
      data['isRead'] = true
      forget_unread
    end
    attachments = data['hasAttachments'] || data.dig('body', 'content').to_s.include?('cid:') ? attachment_list(id) : []
    summary(data).merge(
      to: people(data['toRecipients']), cc: people(data['ccRecipients']), reply_to: people(data['replyTo']),
      web_link: data['webLink'], attachments: attachments.reject { |item| item[:inline] },
      html: Outsider::Apps::MailHtml.clean(data.dig('body', 'content').to_s, inline_images(attachments))
    )
  end

  def update(id, read: nil, flagged: nil)
    body = {}
    body[:isRead] = read unless read.nil?
    body[:flag] = { flagStatus: flagged ? 'flagged' : 'notFlagged' } unless flagged.nil?
    summary(@client.patch("/me/messages/#{enc(id)}", body)).tap { forget_unread }
  end

  # destination: id da pasta ou nome padrão (deleteditems, archive...)
  def move(id, destination)
    @client.post("/me/messages/#{enc(id)}/move", { destinationId: destination.to_s })
    forget_unread
  end

  # mode: 'new' | 'reply' | 'reply_all' | 'forward'. Monta um rascunho, põe os anexos (grandes vão por sessão de envio)
  # e manda. Fica nos Itens enviados da pessoa, como se tivesse mandado pelo Outlook.
  def deliver(mode:, html:, subject: nil, to: [], cc: [], bcc: [], source_id: nil, files: [])
    draft = create_draft(mode, source_id, subject)
    patch = { body: { contentType: 'HTML', content: compose_body(html, draft) } }
    patch[:subject] = subject.to_s.first(250) if subject.present? && mode == 'new'
    patch[:toRecipients] = recipients(to) if to.present? || mode == 'new' || mode == 'forward'
    patch[:ccRecipients] = recipients(cc) if cc.present?
    patch[:bccRecipients] = recipients(bcc) if bcc.present?
    @client.patch("/me/messages/#{enc(draft['id'])}", patch)
    Array(files).first(MAX_ATTACHMENTS).each { |file| attach(draft['id'], file) }
    @client.post("/me/messages/#{enc(draft['id'])}/send", {})
    true
  end

  # o anexo aos pedaços, direto da Microsoft para quem pediu (nada fica no disco)
  def stream_attachment(message_id, attachment_id, &)
    Outsider::Apps::GraphStream.new(@client).get("/me/messages/#{enc(message_id)}/attachments/#{enc(attachment_id)}/$value", &)
  end

  def attachment_info(message_id, attachment_id)
    data = @client.get("/me/messages/#{enc(message_id)}/attachments/#{enc(attachment_id)}?$select=id,name,contentType,size")
    { name: data['name'].presence || 'anexo', content_type: data['contentType'], size: data['size'].to_i }
  end

  # não lidas da Caixa de entrada, para o número do menu (1 minuto no cache)
  def unread_count
    Rails.cache.fetch(self.class.unread_key(@link), expires_in: 1.minute) do
      @client.get('/me/mailFolders/inbox?$select=unreadItemCount')['unreadItemCount'].to_i
    end
  end

  def forget_unread
    Rails.cache.delete(self.class.unread_key(@link))
  end

  def summary(item)
    {
      id: item['id'], subject: item['subject'].to_s, preview: item['bodyPreview'].to_s.first(200),
      from: person(item['from']) || people(item['toRecipients']).first,
      date: item['receivedDateTime'] || item['sentDateTime'], unread: item['isRead'] == false,
      flagged: item.dig('flag', 'flagStatus') == 'flagged', has_attachments: item['hasAttachments'] == true,
      draft: item['isDraft'] == true
    }
  end

  private

  def enc(value)
    Outsider::Teams::Graph::Client.enc(value)
  end

  def list_path(folder, filter, query)
    base = "/me/mailFolders/#{enc(folder.presence || 'inbox')}/messages"
    params = { '$top' => PAGE, '$select' => SUMMARY_FIELDS }
    if query.present?
      # a busca da Microsoft já vem por relevância/data e não aceita $orderby nem $filter junto
      params['$search'] = "\"#{query.to_s.delete('"\\').first(120)}\""
    else
      params['$orderby'] = 'receivedDateTime desc'
      condition = { 'unread' => 'isRead eq false', 'attachments' => 'hasAttachments eq true',
                    'flagged' => "flag/flagStatus eq 'flagged'" }[filter.to_s]
      # com $orderby, a Microsoft pede a mesma propriedade no começo do $filter
      params['$filter'] = "receivedDateTime ge 1900-01-01T00:00:00Z and #{condition}" if condition
    end
    "#{base}?#{params.to_query}"
  end

  # a "próxima página" vem da própria Microsoft; só aceita endereço do Graph para as mensagens da pessoa
  def next_path(cursor)
    uri = URI.parse(cursor.to_s)
    raise Outsider::Teams::Graph::Client::Error.new('cursor', 422) unless Outsider::Teams::Graph::Client.graph_url?(cursor) &&
                                                                          uri.path.start_with?('/v1.0/me/')

    cursor.to_s
  rescue URI::InvalidURIError
    raise Outsider::Teams::Graph::Client::Error.new('cursor', 422)
  end

  def well_known_ids
    Rails.cache.fetch("outsider:apps:microsoft:folders:#{@link.id}", expires_in: 1.day) do
      requests = WELL_KNOWN.map { |name| { id: name, method: 'GET', url: "/me/mailFolders/#{name}?$select=id" } }
      data = @client.post('/$batch', { requests: requests })
      Array(data['responses']).each_with_object({}) do |item, map|
        map[item['id']] = item.dig('body', 'id') if item['status'].to_i == 200
      end
    end
  end

  def attachment_list(id)
    data = @client.get("/me/messages/#{enc(id)}/attachments?$select=id,name,contentType,size,isInline")
    Array(data['value']).map do |item|
      { id: item['id'], name: item['name'].presence || 'anexo', size: item['size'].to_i, content_type: item['contentType'],
        inline: item['isInline'] == true,
        url: Outsider::Apps::FileToken.url(@link, kind: 'ms_attachment', message_id: id, attachment_id: item['id']) }
    end
  end

  # imagens coladas no corpo (src="cid:image001.png@01DA..."): casam pelo nome do anexo
  def inline_images(attachments)
    attachments.select { |item| item[:content_type].to_s.start_with?('image/') }.to_h { |item| [item[:name].to_s.downcase, item[:url]] }
  end

  def person(value)
    address = value.is_a?(Hash) ? value['emailAddress'] : nil
    return nil unless address.is_a?(Hash) && (address['address'].present? || address['name'].present?)

    { name: address['name'].presence || address['address'], email: address['address'].to_s }
  end

  def people(list)
    Array(list).filter_map { |item| person(item) }
  end

  def recipients(list)
    Array(list).map(&:to_s).map(&:strip).grep(URI::MailTo::EMAIL_REGEXP).uniq.first(MAX_RECIPIENTS)
               .map { |email| { emailAddress: { address: email } } }
  end

  def create_draft(mode, source_id, subject)
    case mode
    when 'reply' then @client.post("/me/messages/#{enc(source_id)}/createReply", {})
    when 'reply_all' then @client.post("/me/messages/#{enc(source_id)}/createReplyAll", {})
    when 'forward' then @client.post("/me/messages/#{enc(source_id)}/createForward", {})
    else @client.post('/me/messages', { subject: subject.to_s.first(250), body: { contentType: 'HTML', content: '' } })
    end
  end

  # resposta e encaminhar: o texto da pessoa em cima e a mensagem original citada embaixo (como o Outlook faz)
  def compose_body(html, draft)
    mine = Outsider::Apps::MailHtml.outgoing(html)
    quoted = draft.dig('body', 'content').to_s
    return mine if quoted.blank?

    quoted.sub(/<body[^>]*>/i) { |tag| "#{tag}#{mine}<br>" }.presence || "#{mine}<br>#{quoted}"
  end

  def attach(draft_id, file)
    file.rewind
    name = file.original_filename.to_s.tr('/\\:*?"<>|', '_').strip.presence || 'arquivo'
    type = file.content_type.presence || 'application/octet-stream'
    if file.size <= SMALL_ATTACHMENT
      @client.post("/me/messages/#{enc(draft_id)}/attachments",
                   { '@odata.type' => '#microsoft.graph.fileAttachment', 'name' => name, 'contentType' => type,
                     'contentBytes' => Base64.strict_encode64(file.read) })
    else
      upload_large(draft_id, file, name)
    end
  end

  # anexo acima de 3 MB: sessão de envio da Microsoft, em pedaços (até 150 MB)
  def upload_large(draft_id, file, name)
    session = @client.post("/me/messages/#{enc(draft_id)}/attachments/createUploadSession",
                           { AttachmentItem: { attachmentType: 'file', name: name, size: file.size } })
    url = session['uploadUrl'].to_s
    raise Outsider::Teams::Graph::Client::Error, 'upload_session' unless url.start_with?('https://')

    offset = 0
    file.rewind
    while (chunk = file.read(UPLOAD_CHUNK))
      last = offset + chunk.bytesize - 1
      response = HTTParty.put(url, body: chunk, timeout: 120,
                                   headers: { 'Content-Type' => 'application/octet-stream', 'Content-Length' => chunk.bytesize.to_s,
                                              'Content-Range' => "bytes #{offset}-#{last}/#{file.size}" })
      raise Outsider::Teams::Graph::Client::Error.new("upload #{response.code}", response.code) unless response.success?

      offset = last + 1
    end
  end
end
