# OUTSIDER: resposta do Chatwoot indo para o Microsoft Teams (Entrega 26), pelo Bot Connector, na conversa do Teams
# guardada na conversa do Chatwoot (Outsider::Teams::Inbound). Texto em markdown; imagens vão como anexo (o Teams busca
# pelo endereço público do Chatwoot) e os outros arquivos como link. Deu certo: a mensagem guarda o id do Teams;
# deu errado: fica com falha e o motivo, como nos outros canais.
class Outsider::Teams::Outbound
  TIMEOUT = 15

  def initialize(connection, message)
    @connection = connection
    @message = message
  end

  def perform
    reference = @message.conversation.additional_attributes.to_h['teams'].to_h
    return fail!('no_reference') if reference['conversation_id'].blank?
    return fail!('service_url') unless Outsider::Teams::Auth.microsoft_host?(reference['service_url'])

    response = HTTParty.post(activities_url(reference), headers: headers, body: activity(reference).to_json, timeout: TIMEOUT)
    return fail!("teams #{response.code}") unless response.success?

    @message.update!(source_id: "teams:#{response.parsed_response.try(:dig, 'id')}", status: :sent)
  rescue Outsider::Teams::Auth::Invalid, HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    fail!(e.message.first(200))
  end

  private

  def activities_url(reference)
    "#{reference['service_url'].chomp('/')}/v3/conversations/#{ERB::Util.url_encode(reference['conversation_id'])}/activities"
  end

  def headers
    { 'Authorization' => "Bearer #{Outsider::Teams::Auth.new(@connection).access_token}", 'Content-Type' => 'application/json' }
  end

  def activity(reference)
    images, files = @message.attachments.partition { |attachment| attachment.file_type == 'image' }
    text = [@message.content.presence, *files.map { |attachment| "📎 [#{attachment.file.filename}](#{attachment.download_url})" }].compact.join("\n\n")
    {
      type: 'message', textFormat: 'markdown', text: text, from: { id: reference['bot_id'] }.compact,
      attachments: images.map { |image| { contentType: image.file.content_type, contentUrl: image.download_url, name: image.file.filename.to_s } }
    }
  end

  def fail!(reason)
    @message.update!(status: :failed, external_error: reason)
    false
  end
end
