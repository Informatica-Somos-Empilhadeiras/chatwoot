# OUTSIDER: arquivos do "Conectar meu Teams" sem guardar nada no Chatwoot. Na mensagem fica só o nome, o tamanho e onde o
# arquivo está (OneDrive da pessoa, SharePoint do canal ou imagem colada no Teams). Miniatura, imagem, visualização e
# download vêm da Microsoft na hora, com o token do dono da área Teams.
#   preview_url: endereço da visualização do OneDrive/SharePoint (só leitura, cabe num iframe; nb=true tira a faixa).
#   content_location / thumbnail_url: endereços temporários da Microsoft (já autenticados). content_location pergunta ao
#     Graph pelo /content (o jeito documentado) e, se não vier, pelo @microsoft.graph.downloadUrl.
#   stream: baixa um endereço temporário da Microsoft aos pedaços (download pelo Chatwoot, zip, encaminhar).
#   hosted_bytes: imagem colada no Teams (hostedContents), lida do Graph e repassada.
#   upload: arquivo mandado pelo Chatwoot vai para o OneDrive da pessoa (chat, pasta "Microsoft Teams Chat Files", com
#     leitura para quem está no chat) ou para a pasta do canal no SharePoint, como o próprio Teams faz.
# media_url: endereço assinado (12 horas) que a tela usa em <img>, <video> e em Baixar, sem sessão
#   (Outsider::TeamsMediaController; Baixar vai para Outsider::TeamsDownloadsController, que entrega o arquivo pelo
#   Chatwoot com o nome certo e explica o erro numa página, em vez de um 404 em branco).
class Outsider::Teams::Graph::Files
  SMALL_UPLOAD = 4.megabytes
  CHUNK = 320.kilobytes * 12
  CHAT_FOLDER = 'Microsoft Teams Chat Files'.freeze
  MAX_HOSTED = 10.megabytes
  MEDIA_PURPOSE = 'outsider_teams_media'.freeze
  MEDIA_PATH = '/outsider/teams/media'.freeze
  DOWNLOAD_PATH = '/outsider/teams/download'.freeze
  ZIP_PATH = '/outsider/teams/zip'.freeze
  ZIP_PURPOSE = 'outsider_teams_zip'.freeze
  # a página do Teams fica aberta o dia todo: com 2 horas, Baixar dava 404 depois do almoço
  MEDIA_EXPIRES = 12.hours
  ZIP_EXPIRES = 15.minutes
  STREAM_TIMEOUT = 60
  IMAGES = %w[png jpg jpeg gif webp bmp heic heif].freeze
  # áudios (inclusive as mensagens de voz do Teams no celular): tocam no próprio Chatwoot
  AUDIOS = %w[m4a mp3 ogg oga opus wav aac weba amr flac].freeze
  # vídeos: aparecem no álbum com a miniatura da Microsoft e tocam no visualizador
  VIDEOS = %w[mp4 mov m4v webm avi mkv 3gp wmv mpeg mpg].freeze
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

  def self.video?(name)
    VIDEOS.include?(extension(name))
  end

  # o tipo do anexo para as telas: image, audio, video ou file (mensagens antigas guardaram áudio e vídeo como file)
  def self.kind_of(attachment)
    return 'image' if attachment['kind'] == 'image'
    return 'audio' if audio?(attachment['name'])
    return 'video' if video?(attachment['name'])

    attachment['kind'].presence || 'file'
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

  # kind: thumb | image | full (imagem inteira) | video | audio | download (Outsider::TeamsDownloadsController)
  def self.media_url(message, index, kind)
    token = verifier.generate({ 'm' => message.id, 'i' => index, 'k' => kind }, expires_in: MEDIA_EXPIRES)
    "#{kind == 'download' ? DOWNLOAD_PATH : MEDIA_PATH}?t=#{token}"
  end

  # vários arquivos num .zip: [[message_id, index], ...] da área Teams de uma ligação
  def self.zip_url(link, items, name)
    token = zip_verifier.generate({ 'l' => link.id, 'items' => items, 'n' => name }, expires_in: ZIP_EXPIRES)
    "#{ZIP_PATH}?t=#{token}"
  end

  def self.zip_verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key(ZIP_PURPOSE), url_safe: true, digest: 'SHA256',
                                                                                                  serializer: JSON)
  end

  def self.read_zip(token)
    data = zip_verifier.verified(token.to_s)
    data.is_a?(Hash) ? data : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, JSON::ParserError
    nil
  end

  # endereço temporário da Microsoft aos pedaços; um erro dela (403, 404...) vira Client::Error com o código
  def self.stream(url)
    raise Outsider::Teams::Graph::Client::Error, 'host' unless microsoft_url?(url)

    response = HTTParty.get(url, stream_body: true, timeout: STREAM_TIMEOUT, follow_redirects: true) do |fragment|
      next if fragment.code.between?(300, 399) # corpo do redirecionamento (a Microsoft às vezes manda para outro endereço dela)
      raise Outsider::Teams::Graph::Client::Error.new("download #{fragment.code}", fragment.code) unless fragment.code.between?(200, 299)

      yield(fragment.to_s)
    end
    # erro sem corpo não passa pelo bloco
    raise Outsider::Teams::Graph::Client::Error.new("download #{response.code}", response.code) unless response.code.between?(200, 299)
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    raise Outsider::Teams::Graph::Client::Error, e.message.first(200)
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

  # antes era só o @microsoft.graph.downloadUrl: quando a resposta vinha sem ele, o Baixar dava um 404 em branco
  def download_url(attachment)
    content_location(attachment)
  end

  def content_location(attachment)
    url = @client.location("#{item_path(attachment)}/content")
    return url if self.class.microsoft_url?(url)

    data = @client.get("#{item_path(attachment)}?$select=id,@microsoft.graph.downloadUrl")
    url = data['@microsoft.graph.downloadUrl'].presence || data['@content.downloadUrl']
    self.class.microsoft_url?(url) ? url : raise(Outsider::Teams::Graph::Client::Error.new('no_download_url', 404))
  end

  # o arquivo inteiro aos pedaços (imagem colada vem do Graph de uma vez; o resto, do endereço temporário)
  def stream(attachment, &)
    return yield(hosted_bytes(attachment)[:body]) if attachment['hosted'].present?

    self.class.stream(content_location(attachment), &)
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
