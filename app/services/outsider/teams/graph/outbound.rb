# OUTSIDER: mensagem escrita na área Teams indo para o Teams em nome do colaborador (Microsoft Graph).
#   Chat: nova mensagem no chat; com citação, "responder citando" (replyWithQuote), igual ao Teams.
#   Canal: resposta na publicação (reply_to_graph_id) ou publicação nova. A citação aparece só no Chatwoot.
# Arquivos já foram para o OneDrive/SharePoint no envio (Outsider::Teams::Graph::Files#upload) e vão como anexo do Teams.
# Imagens pequenas vão dentro da mensagem (hostedContents) e não ficam guardadas aqui: inline = [{ body:, content_type: }].
# "@Nome" de quem está no chat (ou já escreveu no canal) vira menção de verdade no Teams.
# Deu certo: guarda o id do Teams (o aviso da Microsoft sobre a própria mensagem não entra de novo); deu errado: fica com
# falha e o motivo.
class Outsider::Teams::Graph::Outbound
  def initialize(message)
    @message = message
    @thread = message.thread
    @link = @thread.link
  end

  def perform(inline: [])
    response = Outsider::Teams::Graph::Client.new(@link).post(path, request_body(inline))
    save_sent(response)
    @thread.update!(last_message_at: @message.sent_at, last_message_preview: "Você: #{preview}".first(160)) if
      @thread.last_message_at.nil? || @thread.last_message_at <= @message.sent_at
    Outsider::Teams::Graph::Notifier.message(@link, @thread, @message, action: 'updated')
    true
  rescue Outsider::Teams::Graph::Client::Error => e
    @message.update!(status: 'failed', error: e.message.first(250))
    Outsider::Teams::Graph::Notifier.message(@link, @thread, @message, action: 'updated')
    false
  end

  private

  def enc(value)
    Outsider::Teams::Graph::Client.enc(value)
  end

  def quote_id
    @message.quote.to_h['graph_id'].presence
  end

  def path
    if @thread.kind == 'chat'
      base = "/chats/#{enc(@thread.chat_id)}/messages"
      return quote_id ? "#{base}/replyWithQuote" : base
    end

    base = "/teams/#{enc(@thread.team_id)}/channels/#{enc(@thread.channel_id)}/messages"
    @message.reply_to_graph_id.present? ? "#{base}/#{enc(@message.reply_to_graph_id)}/replies" : base
  end

  def request_body(inline)
    message = chat_message(inline)
    @thread.kind == 'chat' && quote_id ? { messageIds: [quote_id], replyMessage: message } : message
  end

  def chat_message(inline)
    html, mentions = content_with_mentions
    references = Array(@message.attachments).select { |attachment| attachment['ref_id'].present? && attachment['hosted'].blank? }
    parts = [html.presence]
    parts += references.map { |attachment| %(<attachment id="#{ERB::Util.html_escape(attachment['ref_id'])}"></attachment>) }
    parts += inline.each_with_index.map { |_image, index| %(<img src="../hostedContents/#{index + 1}/$value">) }
    body = { body: { contentType: 'html', content: parts.compact.join('<br>') } }
    body[:subject] = @message.subject if @message.subject.present? && @thread.channel? && @message.reply_to_graph_id.blank?
    body[:mentions] = mentions if mentions.any?
    if references.any?
      body[:attachments] = references.map do |attachment|
        { id: attachment['ref_id'], contentType: 'reference', contentUrl: attachment['url'], name: attachment['name'] }
      end
    end
    if inline.any?
      body[:hostedContents] = inline.each_with_index.map do |image, index|
        { '@microsoft.graph.temporaryId' => (index + 1).to_s, 'contentBytes' => Base64.strict_encode64(image[:body]),
          'contentType' => image[:content_type] }
      end
    end
    body
  end

  # "@Ana Paula" -> <at id="0">Ana Paula</at> + mentions; nomes maiores primeiro ("@Ana Paula" antes de "@Ana")
  def content_with_mentions
    html = ERB::Util.html_escape(@message.content.to_s)
    mentions = []
    people = Array(@thread.members).select { |member| member['id'].present? && member['name'].present? && member['id'] != @link.ms_user_id }
    people.uniq { |member| member['id'] }.sort_by { |member| -member['name'].length }.each do |member|
      token = ERB::Util.html_escape("@#{member['name']}")
      next unless html.include?(token)

      html = html.sub(token, %(<at id="#{mentions.size}">#{ERB::Util.html_escape(member['name'])}</at>))
      mentions << { id: mentions.size, mentionText: member['name'],
                    mentioned: { user: { id: member['id'], displayName: member['name'], userIdentityType: 'aadUser' } } }
    end
    [html.gsub(/\r?\n/, '<br>'), mentions]
  end

  def save_sent(response)
    attributes = { graph_id: response['id'], status: 'sent', error: nil }
    attributes[:sent_at] = Time.zone.parse(response['createdDateTime'].to_s) if response['createdDateTime'].present?
    attributes[:attachments] = with_hosted_images(response) if Array(@message.attachments).any? { |item| item['pending'] }
    @message.update!(attributes)
  rescue ActiveRecord::RecordNotUnique
    # o aviso da Microsoft chegou antes e já gravou a mesma mensagem: fica só esta
    @thread.messages.where(graph_id: response['id']).where.not(id: @message.id).destroy_all
    @message.update!(attributes)
  end

  # as imagens coladas passam a apontar para onde o Teams guardou (hostedContents da mensagem)
  def with_hosted_images(response)
    urls = response.dig('body', 'content').to_s.scan(/<img[^>]+src="([^"]+)"/i).flatten.map { |url| CGI.unescapeHTML(url) }
                   .select { |url| Outsider::Teams::Graph::Client.graph_url?(url) }
    index = -1
    Array(@message.attachments).filter_map do |attachment|
      next attachment unless attachment['pending']

      index += 1
      urls[index] ? attachment.except('pending').merge('hosted' => urls[index]) : nil
    end
  end

  def preview
    first = Array(@message.attachments).first
    @message.content.presence&.squish || (first ? "📎 #{first['name']}" : '')
  end
end
