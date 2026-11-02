# OUTSIDER: mensagem do Microsoft Teams entrando no Chatwoot (Entrega 26), já com a assinatura conferida
# (Outsider::Teams::Auth). Cada conversa do Teams é um contato da caixa (source_id = id da conversa no Teams):
#   - conversa pessoal (1:1 com o robô): o contato é a pessoa (nome do Teams e o id dela no Microsoft Entra ID);
#   - grupo ou canal (robô mencionado): o contato é o grupo, e cada mensagem vem com o nome de quem escreveu.
# A conversa do Chatwoot é a última não resolvida desse contato (ou uma nova). Guarda na conversa o endereço para
# responder (serviceUrl e id da conversa no Teams). Anexos: arquivos do Teams (link de download que já vem pronto) e
# imagens coladas (baixadas com o token do robô, só de endereços da Microsoft). Mensagem repetida pelo Teams não
# entra duas vezes (source_id).
class Outsider::Teams::Inbound
  include FileTypeHelper

  MAX_ATTACHMENT = 40.megabytes
  FILE_INFO = 'application/vnd.microsoft.teams.file.download.info'.freeze

  def initialize(connection, activity)
    @connection = connection
    @inbox = connection.inbox
    @activity = activity.to_h.deep_stringify_keys
  end

  def perform
    return unless @activity['type'] == 'message'
    return if @activity['id'].present? && conversation_messages.exists?(source_id: source_id)

    text = message_text
    files = attachments
    return if text.blank? && files.empty?

    message = conversation.messages.new(account_id: @connection.account_id, inbox_id: @inbox.id, message_type: :incoming,
                                        sender: contact_inbox.contact, content: text.presence, source_id: source_id)
    files.each { |file| message.attachments.new(account_id: @connection.account_id, file_type: file_type(file[:content_type]), file: file) }
    message.save!
    @connection.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    message
  end

  private

  def teams_conversation
    @activity['conversation'].to_h
  end

  def personal?
    teams_conversation['conversationType'].in?([nil, 'personal'])
  end

  def source_id
    "teams:#{@activity['id']}"
  end

  def conversation_messages
    Message.where(inbox_id: @inbox.id)
  end

  def contact_inbox
    @contact_inbox ||= ContactInboxWithContactBuilder.new(inbox: @inbox, source_id: teams_conversation['id'],
                                                          contact_attributes: contact_attributes).perform
  end

  def contact_attributes
    from = @activity['from'].to_h
    return { name: from['name'].presence, additional_attributes: { 'teams_aad_object_id' => from['aadObjectId'] }.compact } if personal?

    { name: teams_conversation['name'].presence || I18n.t('outsider_teams.group_contact'),
      additional_attributes: { 'teams_conversation_type' => teams_conversation['conversationType'] } }
  end

  def conversation
    @conversation ||= begin
      reference = { 'teams' => { 'conversation_id' => teams_conversation['id'], 'service_url' => @activity['serviceUrl'],
                                 'tenant_id' => teams_conversation['tenantId'], 'bot_id' => @activity.dig('recipient', 'id') } }
      existing = contact_inbox.conversations.where.not(status: :resolved).order(:created_at).last
      if existing
        existing.update!(additional_attributes: existing.additional_attributes.to_h.merge(reference))
        existing
      else
        Conversation.create!(account_id: @connection.account_id, inbox_id: @inbox.id, contact_id: contact_inbox.contact_id,
                             contact_inbox_id: contact_inbox.id, additional_attributes: reference)
      end
    end
  end

  # texto sem a menção ao robô e sem HTML; em grupo, com o nome de quem escreveu
  def message_text
    text = @activity['text'].to_s.gsub(%r{<at>[^<]*</at>}, ' ')
    text = CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(text.gsub(%r{<br\s*/?>|</p>}i, "\n"))).strip
    return text if personal? || text.blank?

    "**#{@activity.dig('from', 'name')}:** #{text}"
  end

  def attachments
    Array(@activity['attachments']).filter_map do |attachment|
      url = attachment['contentType'] == FILE_INFO ? attachment.dig('content', 'downloadUrl') : image_url(attachment)
      download(url, attachment['name'], authorize: attachment['contentType'] != FILE_INFO) if url
    end
  end

  def image_url(attachment)
    attachment['contentUrl'] if attachment['contentType'].to_s.start_with?('image/')
  end

  # imagem colada no Teams só baixa com o token do robô, e o token só vai para endereços da Microsoft
  def download(url, name, authorize:)
    return unless URI.parse(url.to_s).is_a?(URI::HTTPS)
    return if authorize && !Outsider::Teams::Auth.microsoft_host?(url)

    headers = authorize ? { 'Authorization' => "Bearer #{Outsider::Teams::Auth.new(@connection).access_token}" } : {}
    file = Down.download(url, max_size: MAX_ATTACHMENT, headers: headers)
    { io: file, filename: name.presence || file.original_filename || 'arquivo', content_type: file.content_type }
  rescue Down::Error, URI::InvalidURIError, Outsider::Teams::Auth::Invalid => e
    Rails.logger.warn("[outsider_teams] attachment skipped: #{e.class}")
    nil
  end
end
