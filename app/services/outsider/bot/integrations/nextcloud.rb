# OUTSIDER: arquivos do Nextcloud para o bot (conexão do tipo nextcloud: endereço, usuário e senha de app).
#   search      procura pelo nome numa pasta (todas as palavras no nome; as mais novas primeiro)
#   share_link  link público só de leitura, com validade (o WhatsApp baixa o arquivo por ele)
#   folders     subpastas, para escolher a pasta no bloco
# Tudo fica dentro da pasta raiz da conexão: um caminho com ".." ou fora dela é recusado.
class Outsider::Bot::Integrations::Nextcloud
  Http = Outsider::Bot::Integrations::Http
  DAV = 'DAV:'.freeze
  OC = 'http://owncloud.org/ns'.freeze
  SHARES = 'ocs/v2.php/apps/files_sharing/api/v1/shares'.freeze
  MAX_RESULTS = 10
  PROPS = '<d:displayname/><d:getcontenttype/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/><oc:fileid/>'.freeze

  def initialize(connection)
    raise Http::Error, 'not_nextcloud' unless connection&.nextcloud?

    @connection = connection
    @http = Http.new(connection)
  end

  # o id do usuário no Nextcloud (pode ser diferente do login, quando entra com e-mail); o Testar descobre
  def user
    (@user_id || @connection.settings['user_id'].presence || @connection.settings['username']).to_s
  end

  def root
    clean_path(@connection.settings['root_folder'].presence || '/')
  end

  # caminho dentro da raiz da conexão: "/Notas/2026" -> "/Documentos/Notas/2026"
  def within_root(path)
    clean_path("#{root}/#{path}")
  end

  # confere que o arquivo está dentro da pasta raiz (o documento vem das variáveis do fluxo)
  def inside_root?(path)
    path = clean_path(path)
    root == '/' || path == root || path.start_with?("#{root}/")
  rescue Http::Error
    false
  end

  def test
    @user_id = discover_user_id
    response = @http.call('PROPFIND', dav_path(root), headers: { 'Depth' => '1' }, body: propfind_body, content_type: 'application/xml')
    raise Http::Error.new('http_error', "HTTP #{response.status}") unless response.status == 207

    items = entries(response.body).reject { |item| item['caminho'] == root }
    { 'folder' => root, 'user_id' => @user_id, 'entries' => items.first(20).map { |item| { 'name' => item['nome'], 'folder' => item['pasta?'] } } }
  end

  def folders(path)
    folder = within_root(path)
    response = @http.call('PROPFIND', dav_path(folder), headers: { 'Depth' => '1' }, body: propfind_body, content_type: 'application/xml')
    raise Http::Error.new('http_error', "HTTP #{response.status}") unless response.status == 207

    entries(response.body).select { |item| item['pasta?'] && item['caminho'] != folder }
                          .map { |item| { 'name' => item['nome'], 'path' => relative(item['caminho']) } }
                          .sort_by { |item| item['name'].downcase }
  end

  # documentos com todas as palavras no nome, os mais novos primeiro: [{ nome, caminho, pasta, tamanho, tipo, modificado, id }]
  def search(query:, folder: '', extensions: [], limit: 5)
    scope = within_root(folder)
    body = search_body(scope, query.to_s.squish.split.first(6), Array(extensions), limit.to_i.clamp(1, MAX_RESULTS))
    response = @http.call('SEARCH', 'remote.php/dav/', body: body, content_type: 'text/xml; charset=utf-8')
    return [] if response.status == 404
    raise Http::Error.new('http_error', "HTTP #{response.status}") unless response.status == 207

    entries(response.body).reject { |item| item['pasta?'] }.map { |item| item.except('pasta?').merge('conexao' => @connection.id) }
  end

  # { 'id', 'url' } de um link público só de leitura que vence em days dias
  def share_link(path, days:)
    raise Http::Error, 'outside_root' unless inside_root?(path)

    form = URI.encode_www_form(path: clean_path(path), shareType: 3, permissions: 1, expireDate: (Date.current + days.to_i.clamp(1, 30)).iso8601)
    response = @http.call('POST', "#{SHARES}?format=json", headers: ocs_headers, body: form, content_type: 'application/x-www-form-urlencoded')
    data = response.data.to_h.dig('ocs', 'data')
    return { 'id' => data['id'].to_s, 'url' => data['url'].to_s } if response.success? && data.is_a?(Hash) && data['url'].present?

    raise Http::Error.new('share_failed', response.data.to_h.dig('ocs', 'meta', 'message').presence || "HTTP #{response.status}")
  end

  def delete_share(id)
    @http.call('DELETE', "#{SHARES}/#{ERB::Util.url_encode(id.to_s)}?format=json", headers: ocs_headers) if id.present?
  rescue Http::Error => e
    Rails.logger.warn("[Outsider::Bot::Nextcloud] não apagou o link #{id}: #{e.code}")
  end

  def web_url(file_id)
    @connection.nextcloud_file_url(file_id)
  end

  private

  def discover_user_id
    response = @http.call('GET', 'ocs/v2.php/cloud/user?format=json', headers: ocs_headers)
    response.data.to_h.dig('ocs', 'data', 'id').presence if response.success?
  rescue Http::Error
    nil
  end

  def ocs_headers
    { 'OCS-APIRequest' => 'true', 'Accept' => 'application/json' }
  end

  def clean_path(path)
    parts = path.to_s.tr('\\', '/').split('/').map(&:strip).compact_blank
    raise Http::Error, 'invalid_path' if parts.any? { |part| part.match?(/\A\.+\z/) }

    "/#{parts.join('/')}"
  end

  def relative(path)
    root == '/' ? path : path.delete_prefix(root).presence || '/'
  end

  def dav_path(path)
    "remote.php/dav/files/#{ERB::Util.url_encode(user)}#{encode_segments(path)}"
  end

  def encode_segments(path)
    path.split('/').compact_blank.map { |part| "/#{ERB::Util.url_encode(part)}" }.join
  end

  def propfind_body
    %(<?xml version="1.0" encoding="UTF-8"?><d:propfind xmlns:d="DAV:" xmlns:oc="#{OC}"><d:prop>#{PROPS}</d:prop></d:propfind>)
  end

  def search_body(scope, words, extensions, limit)
    conditions = words.map { |word| like("%#{word}%") }
    extensions = extensions.map { |ext| ext.to_s.downcase.delete('^a-z0-9') }.compact_blank.first(10)
    conditions << either(extensions.map { |ext| like("%.#{ext}") }) if extensions.any?
    conditions << '<d:not><d:eq><d:prop><d:getcontenttype/></d:prop><d:literal>httpd/unix-directory</d:literal></d:eq></d:not>'
    where = conditions.size == 1 ? conditions.first : "<d:and>#{conditions.join}</d:and>"
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:searchrequest xmlns:d="DAV:" xmlns:oc="#{OC}">
        <d:basicsearch>
          <d:select><d:prop>#{PROPS}</d:prop></d:select>
          <d:from><d:scope><d:href>#{xml("/files/#{ERB::Util.url_encode(user)}#{encode_segments(scope)}")}</d:href><d:depth>infinity</d:depth></d:scope></d:from>
          <d:where>#{where}</d:where>
          <d:orderby><d:order><d:prop><d:getlastmodified/></d:prop><d:descending/></d:order></d:orderby>
          <d:limit><d:nresults>#{limit}</d:nresults></d:limit>
        </d:basicsearch>
      </d:searchrequest>
    XML
  end

  def like(pattern)
    "<d:like><d:prop><d:displayname/></d:prop><d:literal>#{xml(pattern)}</d:literal></d:like>"
  end

  def either(conditions)
    conditions.size == 1 ? conditions.first : "<d:or>#{conditions.join}</d:or>"
  end

  def xml(text)
    ERB::Util.html_escape(text)
  end

  def entries(body)
    document = Nokogiri::XML(body.to_s)
    document.xpath('//d:response', 'd' => DAV).filter_map { |node| entry(node) }
  end

  def entry(node)
    path = path_from_href(node.at_xpath('d:href', 'd' => DAV)&.text.to_s)
    return unless path

    prop = ->(name) { node.at_xpath(".//d:propstat[contains(d:status, '200')]/d:prop/#{name}", 'd' => DAV, 'o' => OC) }
    folder = prop.call('d:resourcetype')&.at_xpath('d:collection', 'd' => DAV).present?
    {
      'nome' => prop.call('d:displayname')&.text.presence || File.basename(path), 'caminho' => path, 'pasta' => File.dirname(path),
      'tamanho' => prop.call('d:getcontentlength')&.text.to_i, 'tipo' => prop.call('d:getcontenttype')&.text.presence || 'application/octet-stream',
      'modificado' => modified(prop.call('d:getlastmodified')&.text), 'id' => prop.call('o:fileid')&.text.to_s, 'pasta?' => folder
    }
  end

  # /remote.php/dav/files/<usuário>/Pasta/NF%20123.pdf -> /Pasta/NF 123.pdf (o "+" continua "+")
  def path_from_href(href)
    decoded = URI.decode_uri_component(href)
    marker = "/remote.php/dav/files/#{user}"
    index = decoded.index(marker)
    return unless index

    "/#{decoded[(index + marker.length)..].to_s.split('/').compact_blank.join('/')}"
  end

  def modified(text)
    Time.httpdate(text.to_s).in_time_zone(Outsider::Bot::Template::TIMEZONE).iso8601
  rescue ArgumentError
    nil
  end
end
