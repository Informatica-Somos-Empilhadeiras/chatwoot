# OUTSIDER: Google Drive no bloco Google (Aplicativos), com o login da pessoa (permissão drive). Espelho: a lista, a prévia
# e o download vêm do Google na hora; o Chatwoot não guarda nenhum arquivo. Abrir e Baixar passam pelo Chatwoot aos
# pedaços (link assinado, Outsider::AppsFilesController), porque o Google só entrega o arquivo com o token da pessoa.
# Documentos, Planilhas e Apresentações do Google abrem como PDF e baixam como Word, Excel e PowerPoint.
#
# Mesmo formato do OneDrive (Outsider::Apps::Microsoft::Drive):
#   item: { id, drive_id, name, folder, size, mime, modified_at, modified_by, web_url, child_count }
class Outsider::Apps::Google::Drive
  PAGE = 50
  CHUNK = 256.kilobytes * 32 # 8 MB; o envio em partes do Google pede múltiplos de 256 KB
  FOLDER = 'application/vnd.google-apps.folder'.freeze
  SHORTCUT = 'application/vnd.google-apps.shortcut'.freeze
  FIELDS = 'id,name,mimeType,size,modifiedTime,lastModifyingUser(displayName),webViewLink,driveId,shortcutDetails,trashed'.freeze
  # tipo do Google => [prévia, download (tipo, extensão)]
  NATIVE = {
    'application/vnd.google-apps.document' => ['application/pdf',
                                               ['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx']],
    'application/vnd.google-apps.spreadsheet' => ['application/pdf',
                                                  ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'xlsx']],
    'application/vnd.google-apps.presentation' => ['application/pdf',
                                                   ['application/vnd.openxmlformats-officedocument.presentationml.presentation', 'pptx']],
    'application/vnd.google-apps.drawing' => ['application/pdf', ['application/pdf', 'pdf']]
  }.freeze
  IMAGES = %w[image/png image/jpeg image/gif image/webp image/bmp].freeze
  TEXT = %w[text/plain text/csv application/json text/xml text/markdown].freeze

  def initialize(link)
    @link = link
    @client = Outsider::Apps::Google::Client.new(link)
  end

  # view: 'mine' (uma pasta: folder_id vazio = Meu Drive) | 'shared' (compartilhados comigo) | 'recent'
  def list(view: 'mine', folder_id: nil, query: nil, cursor: nil)
    state = cursor.present? ? read_cursor(cursor) : { 'v' => view.to_s, 'f' => folder_id.to_s, 'q' => query.to_s.first(120) }
    params = list_params(state).merge(pageSize: PAGE, fields: "nextPageToken,files(#{FIELDS})", supportsAllDrives: true,
                                      includeItemsFromAllDrives: true, pageToken: state['p'].presence)
    data = @client.get("#{base}/files", query: params)
    items = Array(data['files']).map { |item| item_json(item) }
    { items: items, next: data['nextPageToken'].present? ? write_cursor(state.merge('p' => data['nextPageToken'])) : nil }
  end

  def item(_drive_id, id)
    item_json(raw_item(id))
  end

  # o arquivo com a miniatura do Google (pelo Chatwoot, porque a miniatura também pede o token), para o painel ao lado
  def details(_drive_id, id)
    data = @client.get("#{base}/files/#{enc(id)}", query: { fields: "#{FIELDS},hasThumbnail,shared", supportsAllDrives: true })
    thumb = data['hasThumbnail'] ? Outsider::Apps::FileToken.url(@link, kind: 'g_thumb', file_id: data['id']) : nil
    item_json(data).merge(thumbnail: thumb, shared: data['shared'] ? 'users' : nil)
  end

  # link assinado para baixar pelo Chatwoot (Documentos do Google viram Word, Excel e PowerPoint)
  def download_url(_drive_id, id)
    info = raw_item(id)
    mime = info['mimeType'].to_s
    # Formulário, Site, Mapa... do Google não têm arquivo para baixar
    raise Outsider::Apps::Google::Client::Error.new('not_downloadable', 422) if mime.start_with?('application/vnd.google-apps') && !NATIVE.key?(mime)

    "#{file_url(info, download: true)}&download=1"
  end

  # prévia para o visualizador do Chatwoot: { kind, view_url, download_url, edit_url }
  def preview(_drive_id, id)
    info = raw_item(id)
    item = item_json(info)
    mime = info['mimeType'].to_s
    download = "#{file_url(info, download: true)}&download=1"
    base_info = item.merge(download_url: download, edit_url: info['webViewLink'])
    return base_info.merge(kind: 'pdf', view_url: export_url(info, 'application/pdf')) if NATIVE.key?(mime)
    return base_info.merge(kind: 'none', reason: 'preview', view_url: nil, download_url: nil) if mime.start_with?('application/vnd.google-apps')
    return base_info.merge(kind: 'image', view_url: file_url(info)) if IMAGES.include?(mime)
    return base_info.merge(kind: 'video', view_url: file_url(info)) if mime.start_with?('video/')
    return base_info.merge(kind: 'pdf', view_url: file_url(info)) if mime == 'application/pdf'
    return base_info.merge(kind: 'text', view_url: file_url(info)) if TEXT.include?(mime) && info['size'].to_i <= 2.megabytes

    base_info.merge(office_preview(info))
  end

  def create_folder(_drive_id, parent_id, name)
    body = { name: clean_name(name), mimeType: FOLDER, parents: [parent_id.presence || 'root'] }
    item_json(@client.post("#{base}/files", body, query: { fields: FIELDS, supportsAllDrives: true }))
  end

  # file: ActionDispatch::Http::UploadedFile; envio em partes do Google (sessão), 8 MB por vez
  def upload(_drive_id, parent_id, file)
    meta = { name: clean_name(file.original_filename), parents: [parent_id.presence || 'root'] }
    type = file.content_type.presence || 'application/octet-stream'
    query = { uploadType: 'resumable', supportsAllDrives: true, fields: FIELDS }
    headers = { 'X-Upload-Content-Type' => type, 'X-Upload-Content-Length' => file.size.to_s }
    start = @client.raw(:post, "#{Outsider::Apps::Google::Client::DRIVE_UPLOAD}/files", body: meta.to_json, query: query,
                                                                                        content_type: 'application/json; charset=UTF-8',
                                                                                        headers: headers)
    session = start.headers['location'].to_s
    raise Outsider::Apps::Google::Client::Error, 'upload_session' unless Outsider::Apps::Google::Client.google_url?(session)

    item_json(send_chunks(session, file, type))
  end

  # scope: 'organization' = o link do arquivo (abre para quem já tem acesso) | 'anonymous' = qualquer pessoa com o link
  def share_link(_drive_id, id, scope: 'organization')
    if scope.to_s == 'anonymous'
      @client.post("#{base}/files/#{enc(id)}/permissions", { role: 'reader', type: 'anyone' }, query: { supportsAllDrives: true })
    end
    raw_item(id)['webViewLink']
  end

  # vai para a Lixeira do Drive (30 dias para recuperar)
  def delete(_drive_id, id)
    @client.patch("#{base}/files/#{enc(id)}", { trashed: true }, query: { supportsAllDrives: true })
    true
  end

  # o que o link assinado precisa para entregar o arquivo: { name, content_type, url, query }
  def source(data)
    case data['k']
    when 'g_file'
      info = raw_item(data['file_id'])
      { name: info['name'], content_type: info['mimeType'], url: "#{base}/files/#{enc(info['id'])}",
        query: { alt: 'media', supportsAllDrives: true } }
    when 'g_export'
      info = raw_item(data['file_id'])
      ext = data['ext'].presence || 'pdf'
      { name: "#{File.basename(info['name'].to_s, '.*').presence || 'arquivo'}.#{ext}", content_type: data['mime'],
        url: "#{base}/files/#{enc(info['id'])}/export", query: { mimeType: data['mime'] } }
    end
  end

  def thumbnail(file_id)
    link = @client.get("#{base}/files/#{enc(file_id)}", query: { fields: 'thumbnailLink', supportsAllDrives: true })['thumbnailLink']
    raise Outsider::Apps::Google::Client::Error.new('not_found', 404) if link.blank?

    @client.bytes(link.sub(/=s\d+\z/, '=s640'), max: 3.megabytes)
  end

  def stream(source, &)
    @client.stream(source[:url], query: source[:query], &)
  end

  private

  def base
    Outsider::Apps::Google::Client::DRIVE
  end

  def enc(value)
    Outsider::Apps::Google::Client.enc(value)
  end

  def raw_item(id)
    data = @client.get("#{base}/files/#{enc(id)}", query: { fields: FIELDS, supportsAllDrives: true })
    return data unless data['mimeType'] == SHORTCUT && data.dig('shortcutDetails', 'targetId').present?

    @client.get("#{base}/files/#{enc(data.dig('shortcutDetails', 'targetId'))}", query: { fields: FIELDS, supportsAllDrives: true })
  end

  def clean_name(name)
    name.to_s.tr('/\\:*?"<>|', '_').strip.first(200).presence || 'arquivo'
  end

  def list_params(state)
    text = state['q'].to_s.delete('\\').gsub("'", "\\\\'")
    return { q: "(name contains '#{text}' or fullText contains '#{text}') and trashed = false" } if state['q'].present?
    return { q: "'#{state['f'].delete("'\\")}' in parents and trashed = false", orderBy: 'folder,name_natural' } if state['f'].present?
    return { q: 'sharedWithMe and trashed = false', orderBy: 'sharedWithMeTime desc' } if state['v'] == 'shared'
    return { q: "trashed = false and mimeType != '#{FOLDER}'", orderBy: 'recency desc' } if state['v'] == 'recent'

    { q: "'root' in parents and trashed = false", orderBy: 'folder,name_natural' }
  end

  def write_cursor(state)
    Base64.urlsafe_encode64(state.to_json, padding: false)
  end

  def read_cursor(cursor)
    data = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
    raise ArgumentError unless data.is_a?(Hash)

    data.slice('v', 'f', 'q', 'p').transform_values(&:to_s)
  rescue ArgumentError, JSON::ParserError
    raise Outsider::Apps::Google::Client::Error.new('cursor', 422)
  end

  # atalho do Drive: mostra o destino (pasta abre como pasta)
  def item_json(item)
    mime = item['mimeType'].to_s
    target = mime == SHORTCUT ? item['shortcutDetails'].to_h : {}
    real_mime = target['targetMimeType'].presence || mime
    {
      id: target['targetId'].presence || item['id'], drive_id: item['driveId'], name: item['name'], folder: real_mime == FOLDER,
      size: item['size'].presence&.to_i, mime: real_mime, modified_at: item['modifiedTime'],
      modified_by: item.dig('lastModifyingUser', 'displayName'), web_url: item['webViewLink'], child_count: nil
    }
  end

  # download: Documento do Google vira Word/Excel/PowerPoint; o resto é o próprio arquivo
  def file_url(info, download: false)
    native = NATIVE[info['mimeType'].to_s]
    return export_url(info, native[1][0], native[1][1]) if native && download

    Outsider::Apps::FileToken.url(@link, kind: 'g_file', file_id: info['id'])
  end

  def export_url(info, mime, ext = 'pdf')
    Outsider::Apps::FileToken.url(@link, kind: 'g_export', file_id: info['id'], mime: mime, ext: ext)
  end

  # Word, Excel e PowerPoint: pelo visualizador do Office na web (busca o arquivo no link assinado; só com endereço
  # público, como nos anexos das conversas). Sem isso, a visualização do próprio Google (pede o login do Google no navegador).
  def office_preview(info)
    ext = File.extname(info['name'].to_s).delete('.').downcase
    group = if Outsider::FileView::WORD.include?(ext) then 'word'
            elsif Outsider::FileView::EXCEL.include?(ext) then 'excel'
            elsif Outsider::FileView::POWERPOINT.include?(ext) then 'powerpoint'
            end
    if group && Outsider::FileView.public_site? && info['size'].to_i <= Outsider::FileView::OFFICE_LIMIT[group]
      name = File.basename(info['name'].to_s, '.*').parameterize.presence || 'arquivo'
      path = file_url(info).sub(Outsider::Apps::FileToken::PATH, "#{Outsider::Apps::FileToken::PATH}/#{name.first(80)}.#{ext}")
      src = "#{Outsider::FileView.site}#{path}"
      return { kind: 'office', view_url: "#{Outsider::FileView::OFFICE_VIEWER}#{ERB::Util.url_encode(src)}" }
    end
    { kind: 'preview', view_url: "https://drive.google.com/file/d/#{enc(info['id'])}/preview" }
  end

  def send_chunks(session, file, type)
    return put_chunk(session, '', type, 'bytes */0').parsed_response.to_h unless file.size.positive?

    offset = 0
    file.rewind
    while (chunk = file.read(CHUNK))
      last = offset + chunk.bytesize - 1
      response = put_chunk(session, chunk, type, "bytes #{offset}-#{last}/#{file.size}")
      return response.parsed_response if response.success? && response.parsed_response.is_a?(Hash)
      raise Outsider::Apps::Google::Client::Error.new("upload #{response.code}", response.code) unless response.code == 308

      offset = last + 1
    end
    raise Outsider::Apps::Google::Client::Error, 'upload_incomplete'
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Outsider::Apps::Google::Client::Error, e.message.first(200)
  end

  # o endereço da sessão de envio já é autorizado pelo Google (não leva o token)
  def put_chunk(session, chunk, type, range)
    HTTParty.put(session, body: chunk, timeout: 120, follow_redirects: false,
                          headers: { 'Content-Type' => type, 'Content-Length' => chunk.bytesize.to_s, 'Content-Range' => range })
  end
end
