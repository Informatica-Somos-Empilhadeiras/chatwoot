# OUTSIDER: arquivos do "Conectar meu Teams" sem guardar nada no Chatwoot. Na mensagem fica só o nome, o tamanho e onde o
# arquivo está (OneDrive da pessoa, SharePoint do canal ou imagem colada no Teams). Miniatura, imagem, visualização e
# download vêm da Microsoft na hora, com o token do dono da área Teams.
#   preview_url: endereço da visualização do OneDrive/SharePoint (só leitura, cabe num iframe; nb=true tira a faixa).
#   download_url / thumbnail_url: endereços temporários da Microsoft (já autenticados).
#   hosted_bytes: imagem colada no Teams (hostedContents), lida do Graph e repassada.
#   upload: arquivo mandado pelo Chatwoot vai para o OneDrive da pessoa (chat, pasta "Microsoft Teams Chat Files", com
#     leitura para quem está no chat) ou para a pasta do canal no SharePoint, como o próprio Teams faz.
# media_url: endereço assinado (2 horas) que a tela usa em <img> e em Baixar, sem sessão (Outsider::TeamsMediaController).
class Outsider::Teams::Graph::Files
  SMALL_UPLOAD = 4.megabytes
  CHUNK = 320.kilobytes * 12
  CHAT_FOLDER = 'Microsoft Teams Chat Files'.freeze
  MAX_HOSTED = 10.megabytes
  MEDIA_PURPOSE = 'outsider_teams_media'.freeze
  MEDIA_PATH = '/outsider/teams/media'.freeze
  MEDIA_EXPIRES = 2.hours
  IMAGES = %w[png jpg jpeg gif webp bmp heic heif].freeze
  # áudios (inclusive as mensagens de voz do Teams no celular): tocam no próprio Chatwoot
  AUDIOS = %w[m4a mp3 ogg oga opus wav aac weba amr flac].freeze
  MICROSOFT_HOSTS = %w[sharepoint.com svc.ms microsoft.com office.com office.net live.com microsoftpersonalcontent.com 1drv.com
                       onedrive.com sharepointonline.com].freeze

  def self.share_id(url)
    "u!#{Base64.urlsafe_encode64(url.to_s, padding: false)}"
  end

  def self.extension(name)
    File.extname(name.to_s).delete('.').downcase
  end

  def self.image?(name)
    IMAGES.include?(extension(name))
  end

  def self.audio?(name)
    AUDIOS.include?(extension(name))
  end

  # o tipo do anexo para as telas: image, audio ou file (mensagens antigas guardaram áudio como file)
  def self.kind_of(attachment)
    return 'image' if attachment['kind'] == 'image'

    audio?(attachment['name']) ? 'audio' : attachment['kind'].presence || 'file'
  end

  def self.source(url)
    host = URI.parse(url.to_s).host.to_s
    return 'onedrive' if host.end_with?('-my.sharepoint.com') || host.include?('onedrive') || host.end_with?('1drv.com')

    host.end_with?('sharepoint.com') ? 'sharepoint' : 'link'
  rescue URI::InvalidURIError
    'link'
  end

  def self.microsoft_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && MICROSOFT_HOSTS.any? { |host| uri.host.to_s == host || uri.host.to_s.end_with?(".#{host}") }
  rescue URI::InvalidURIError
    false
  end

  def self.verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key(MEDIA_PURPOSE), url_safe: true, digest: 'SHA256',
                                                                                                    serializer: JSON)
  end

  # kind: thumb | image | download | audio (tocar no Chatwoot: o endereço temporário da Microsoft)
  def self.media_url(message, index, kind)
    token = verifier.generate({ 'm' => message.id, 'i' => index, 'k' => kind }, expires_in: MEDIA_EXPIRES)
    "#{MEDIA_PATH}?t=#{token}"
  end

  def self.read_media(token)
    data = verifier.verified(token.to_s)
    data.is_a?(Hash) ? data : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, JSON::ParserError
    nil
  end

  def initialize(link)
    @link = link
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  # ids do arquivo no OneDrive/SharePoint (o Teams só manda o endereço): descobre uma vez e guarda na própria mensagem
  def resolve!(message, index)
    attachment = message.attachments[index].to_h
    return attachment if attachment['drive_id'].present? || attachment['hosted'].present?

    item = @client.get("/shares/#{self.class.share_id(attachment['url'])}/driveItem?$select=id,name,size,webUrl,file,parentReference")
    attachment = attachment.merge('drive_id' => item.dig('parentReference', 'driveId'), 'item_id' => item['id'],
                                  'web_url' => item['webUrl'], 'size' => item['size'], 'mime' => item.dig('file', 'mimeType'))
    list = message.attachments.dup
    list[index] = attachment
    message.update_columns(attachments: list) # rubocop:disable Rails/SkipsModelValidations
    attachment
  end

  def preview_url(attachment)
    url = @client.post("#{item_path(attachment)}/preview", {})['getUrl'].to_s
    return nil unless url.start_with?('https://')

    "#{url}#{url.include?('?') ? '&' : '?'}nb=true"
  end

  def download_url(attachment)
    url = @client.get("#{item_path(attachment)}?$select=id,@microsoft.graph.downloadUrl")['@microsoft.graph.downloadUrl']
    self.class.microsoft_url?(url) ? url : nil
  end

  def thumbnail_url(attachment, size = 'medium')
    url = Array(@client.get("#{item_path(attachment)}/thumbnails?$select=#{size}")['value']).first&.dig(size, 'url')
    self.class.microsoft_url?(url) ? url : nil
  end

  def hosted_bytes(attachment)
    @client.bytes(attachment['hosted'], max: MAX_HOSTED)
  end

  # file: ActionDispatch::Http::UploadedFile. Devolve o anexo para guardar na mensagem e mandar ao Teams.
  def upload(thread, file)
    name = file.original_filename.to_s.tr('/\\:*?"<>|', '_').strip.presence || 'arquivo'
    target = if thread.channel?
               folder = channel_folder(thread)
               "/drives/#{enc(folder['drive_id'])}/items/#{enc(folder['item_id'])}:/#{enc(name)}:"
             else
               "/me/drive/root:/#{enc(CHAT_FOLDER)}/#{enc(name)}:"
             end
    file.rewind
    item = if file.size <= SMALL_UPLOAD
             @client.put_bytes("#{target}/content?@microsoft.graph.conflictBehavior=rename", file.read, file.content_type)
           else
             upload_session(target, file)
           end
    share_with_members(thread, item) unless thread.channel?
    attachment_from(item, file.content_type)
  end

  private

  def enc(value)
    Outsider::Teams::Graph::Client.enc(value)
  end

  def item_path(attachment)
    raise Outsider::Teams::Graph::Client::Error, 'not_resolved' if attachment['drive_id'].blank? || attachment['item_id'].blank?

    "/drives/#{enc(attachment['drive_id'])}/items/#{enc(attachment['item_id'])}"
  end

  def channel_folder(thread)
    Rails.cache.fetch("outsider_teams_folder:#{thread.id}", expires_in: 1.day) do
      data = @client.get("/teams/#{enc(thread.team_id)}/channels/#{enc(thread.channel_id)}/filesFolder")
      { 'drive_id' => data.dig('parentReference', 'driveId'), 'item_id' => data['id'] }
    end
  end

  # arquivo grande: sessão de envio da Microsoft, em pedaços múltiplos de 320 KB (o endereço da sessão já é autenticado)
  def upload_session(target, file)
    session = @client.post("#{target}/createUploadSession", { item: { '@microsoft.graph.conflictBehavior' => 'rename' } })
    url = session['uploadUrl'].to_s
    raise Outsider::Teams::Graph::Client::Error, 'upload_url' unless self.class.microsoft_url?(url)

    size = file.size
    offset = 0
    result = nil
    while offset < size
      chunk = file.read(CHUNK)
      last = offset + chunk.bytesize - 1
      response = HTTParty.put(url, body: chunk, timeout: 120,
                                   headers: { 'Content-Length' => chunk.bytesize.to_s, 'Content-Range' => "bytes #{offset}-#{last}/#{size}" })
      raise Outsider::Teams::Graph::Client::Error.new("upload #{response.code}", response.code) unless response.success?

      result = response.parsed_response if response.code.in?([200, 201])
      offset = last + 1
    end
    result.is_a?(Hash) ? result : raise(Outsider::Teams::Graph::Client::Error, 'upload')
  end

  # no chat o arquivo fica no OneDrive de quem mandou: quem está no chat ganha leitura (sem e-mail de convite)
  def share_with_members(thread, item)
    ids = Array(thread.members).filter_map { |member| member['id'].presence }.reject { |id| id == @link.ms_user_id }.uniq.first(50)
    return if ids.empty?

    @client.post("/drives/#{enc(item.dig('parentReference', 'driveId'))}/items/#{enc(item['id'])}/invite",
                 { recipients: ids.map { |id| { objectId: id } }, requireSignIn: true, sendInvitation: false, roles: ['read'] })
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_teams_graph] share skipped: #{e.message}")
  end

  def attachment_from(item, content_type)
    {
      'kind' => self.class.image?(item['name']) ? 'image' : 'file', 'name' => item['name'], 'size' => item['size'],
      'mime' => item.dig('file', 'mimeType').presence || content_type, 'url' => item['webDavUrl'].presence || item['webUrl'],
      'web_url' => item['webUrl'], 'drive_id' => item.dig('parentReference', 'driveId'), 'item_id' => item['id'],
      'source' => self.class.source(item['webUrl']), 'ref_id' => item['eTag'].to_s[/\{([0-9A-Fa-f-]{36})\}/, 1]&.downcase
    }
  end
end
