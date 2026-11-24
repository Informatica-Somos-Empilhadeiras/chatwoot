# OUTSIDER: OneDrive no bloco Microsoft (Aplicativos), pelo login do "Conectar meu Teams" (Files.ReadWrite.All, já
# concedida desde a primeira versão). Espelho: a lista, a prévia e o download vêm da Microsoft na hora; o Chatwoot não
# guarda nenhum arquivo. Baixar devolve o endereço temporário da própria Microsoft (o arquivo vai direto para o
# navegador, sem passar pelo servidor); Enviar passa pelo servidor só o tempo de mandar para a Microsoft.
#
# Formato comum dos aplicativos (o Google Drive usa o mesmo):
#   item: { id, drive_id, name, folder, size, mime, modified_at, modified_by, web_url, child_count }
class Outsider::Apps::Microsoft::Drive
  PAGE = 50
  SMALL_UPLOAD = 4.megabytes
  UPLOAD_CHUNK = 320.kilobytes * 12
  FIELDS = 'id,name,size,folder,file,lastModifiedDateTime,lastModifiedBy,webUrl,parentReference,remoteItem,package'.freeze

  def initialize(link)
    @link = link
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  # view: 'mine' (uma pasta: folder_id vazio = raiz) | 'shared' (compartilhados comigo) | 'recent'
  def list(view: 'mine', drive_id: nil, folder_id: nil, query: nil, cursor: nil)
    data = @client.get(cursor.present? ? next_path(cursor) : list_path(view, drive_id, folder_id, query))
    items = Array(data['value']).map { |item| item_json(item) }
    items = items.sort_by { |item| [item[:folder] ? 0 : 1, item[:name].to_s.downcase] } if view == 'mine' && query.blank?
    { items: items, next: data['@odata.nextLink'].presence }
  end

  def item(drive_id, id)
    item_json(@client.get("#{item_path(drive_id, id)}?$select=#{FIELDS}"))
  end

  # o arquivo com a miniatura da Microsoft (primeira página/foto, endereço temporário dela), para o painel ao lado
  def details(drive_id, id)
    data = @client.get("#{item_path(drive_id, id)}?$select=#{FIELDS},shared&$expand=thumbnails($select=large)")
    thumb = Array(data['thumbnails']).first&.dig('large', 'url')
    item_json(data).merge(thumbnail: Outsider::Teams::Graph::Files.microsoft_url?(thumb) ? thumb : nil,
                          shared: data.dig('shared', 'scope'))
  end

  # endereço temporário da Microsoft (já autenticado, alguns minutos): o navegador baixa direto
  def download_url(drive_id, id)
    url = @client.location("#{item_path(drive_id, id)}/content")
    return url if Outsider::Teams::Graph::Files.microsoft_url?(url)

    data = @client.get("#{item_path(drive_id, id)}?$select=id,@microsoft.graph.downloadUrl")
    url = data['@microsoft.graph.downloadUrl'].presence
    Outsider::Teams::Graph::Files.microsoft_url?(url) ? url : raise(Outsider::Teams::Graph::Client::Error.new('no_download_url', 404))
  end

  # prévia para o visualizador do Chatwoot: { kind, view_url, download_url, edit_url }
  def preview(drive_id, id)
    info = item(drive_id, id)
    ext = File.extname(info[:name].to_s).delete('.').downcase
    if Outsider::Teams::Graph::Files::IMAGES.include?(ext) || Outsider::Teams::Graph::Files::VIDEOS.include?(ext)
      url = download_url(drive_id, id)
      kind = Outsider::Teams::Graph::Files::IMAGES.include?(ext) ? 'image' : 'video'
      return info.merge(kind: kind, view_url: url, download_url: url, edit_url: info[:web_url])
    end

    view = @client.post("#{item_path(drive_id, id)}/preview", {})['getUrl'].to_s
    view = if view.start_with?('https://')
             "#{view}#{view.include?('?') ? '&' : '?'}nb=true"
           end
    info.merge(kind: view ? 'office' : 'none', reason: view ? nil : 'preview', view_url: view, edit_url: info[:web_url])
  end

  def create_folder(drive_id, parent_id, name)
    body = { 'name' => clean_name(name), 'folder' => {}, '@microsoft.graph.conflictBehavior' => 'rename' }
    item_json(@client.post("#{parent_path(drive_id, parent_id)}/children", body))
  end

  # file: ActionDispatch::Http::UploadedFile; até 4 MB de uma vez, acima disso em pedaços (sessão de envio)
  def upload(drive_id, parent_id, file)
    name = clean_name(file.original_filename)
    target = "#{parent_path(drive_id, parent_id)}:/#{enc(name)}:"
    file.rewind
    item = if file.size <= SMALL_UPLOAD
             @client.put_bytes("#{target}/content?@microsoft.graph.conflictBehavior=rename", file.read, file.content_type)
           else
             upload_session(target, file)
           end
    item_json(item)
  end

  # scope: 'organization' (só a empresa) | 'anonymous' (qualquer pessoa com o link; a empresa pode ter bloqueado)
  def share_link(drive_id, id, scope: 'organization')
    scope = %w[organization anonymous].include?(scope.to_s) ? scope.to_s : 'organization'
    @client.post("#{item_path(drive_id, id)}/createLink", { type: 'view', scope: scope }).dig('link', 'webUrl')
  end

  # vai para a Lixeira do OneDrive (dá para recuperar por lá)
  def delete(drive_id, id)
    @client.delete(item_path(drive_id, id))
    true
  end

  private

  def enc(value)
    Outsider::Teams::Graph::Client.enc(value)
  end

  def clean_name(name)
    name.to_s.tr('/\\:*?"<>|#%', '_').strip.first(200).presence || 'arquivo'
  end

  def item_path(drive_id, id)
    drive_id.present? ? "/drives/#{enc(drive_id)}/items/#{enc(id)}" : "/me/drive/items/#{enc(id)}"
  end

  def parent_path(drive_id, parent_id)
    return item_path(drive_id, parent_id) if parent_id.present?

    drive_id.present? ? "/drives/#{enc(drive_id)}/root" : '/me/drive/root'
  end

  def list_path(view, drive_id, folder_id, query)
    params = { '$top' => PAGE, '$select' => FIELDS }
    return "/me/drive/root/search(q='#{enc(query.to_s.delete("'").first(120))}')?#{params.to_query}" if query.present?
    return "/me/drive/sharedWithMe?#{params.except('$select').to_query}" if view == 'shared' && folder_id.blank?
    return "/me/drive/recent?#{params.except('$select').to_query}" if view == 'recent' && folder_id.blank?

    "#{parent_path(drive_id, folder_id)}/children?#{params.to_query}"
  end

  def next_path(cursor)
    uri = URI.parse(cursor.to_s)
    ok = Outsider::Teams::Graph::Client.graph_url?(cursor) && uri.path.match?(%r{\A/v1\.0/(me|drives)/})
    raise Outsider::Teams::Graph::Client::Error.new('cursor', 422) unless ok

    cursor.to_s
  rescue URI::InvalidURIError
    raise Outsider::Teams::Graph::Client::Error.new('cursor', 422)
  end

  # compartilhados e recentes vêm como "remoteItem" (o arquivo está no OneDrive de outra pessoa ou no SharePoint)
  def item_json(item)
    remote = item['remoteItem'].is_a?(Hash) ? item['remoteItem'] : nil
    source = remote || item
    {
      id: source['id'], drive_id: source.dig('parentReference', 'driveId') || item.dig('parentReference', 'driveId'),
      name: item['name'] || source['name'], folder: source['folder'].is_a?(Hash), size: source['size'].to_i,
      mime: source.dig('file', 'mimeType'), modified_at: source['lastModifiedDateTime'] || item['lastModifiedDateTime'],
      modified_by: (source['lastModifiedBy'] || item['lastModifiedBy'])&.dig('user', 'displayName'),
      web_url: source['webUrl'] || item['webUrl'], child_count: source.dig('folder', 'childCount')
    }
  end

  def upload_session(target, file)
    session = @client.post("#{target}/createUploadSession", { item: { '@microsoft.graph.conflictBehavior' => 'rename' } })
    url = session['uploadUrl'].to_s
    raise Outsider::Teams::Graph::Client::Error, 'upload_session' unless url.start_with?('https://')

    offset = 0
    result = nil
    file.rewind
    while (chunk = file.read(UPLOAD_CHUNK))
      last = offset + chunk.bytesize - 1
      response = HTTParty.put(url, body: chunk, timeout: 120,
                                   headers: { 'Content-Length' => chunk.bytesize.to_s, 'Content-Range' => "bytes #{offset}-#{last}/#{file.size}" })
      raise Outsider::Teams::Graph::Client::Error.new("upload #{response.code}", response.code) unless response.success?

      result = response.parsed_response if response.parsed_response.is_a?(Hash) && response.parsed_response['id']
      offset = last + 1
    end
    result || {}
  end
end
