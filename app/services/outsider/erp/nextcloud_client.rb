# OUTSIDER: a conexão com o Nextcloud da Somos (Configurações do ERP: endereço, usuário e senha de app), usada pelas notas
# fiscais (Outsider::Erp::NextcloudInvoices) e pelas fotos dos produtos (Outsider::Erp::ProductPhotos): a busca do próprio
# Nextcloud (WebDAV SEARCH) e o download de um arquivo. Só lê: nada é gravado no Nextcloud nem guardado no chat.
class Outsider::Erp::NextcloudClient
  class Error < StandardError; end

  TIMEOUT = 20
  MAX_BYTES = 20.megabytes
  NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError].freeze

  def initialize(settings)
    @settings = settings
    @base = URI.parse(settings.nextcloud_url)
  end

  # o começo do caminho dos arquivos do usuário nas respostas do Nextcloud (href), já codificado
  def files_root = "#{@base.path}/remote.php/dav/files/#{ERB::Util.url_encode(user_id)}"

  def encoded(path) = path.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')

  # [[href, modificado]] dos arquivos cujo nome bate com o padrão (like, % coringa) em folder e nas subpastas
  def search(folder, pattern)
    response = http.request(search_request(folder, pattern))
    raise Error, "HTTP #{response.code}" unless response.code == '207'

    Nokogiri::XML(response.body).remove_namespaces!.xpath('//response').map do |node|
      [node.at_xpath('href').text, node.at_xpath('.//getlastmodified')&.text.to_s]
    end
  rescue *NETWORK_ERRORS => e
    raise Error, e.class.name
  end

  # os nomes dos arquivos direto numa pasta (sem as subpastas), numa chamada só
  def list(folder)
    response = http.request(list_request(folder))
    raise Error, "HTTP #{response.code}" unless response.code == '207'

    Nokogiri::XML(response.body).remove_namespaces!.xpath('//response[not(.//collection)]/href').map do |href|
      URI.decode_uri_component(File.basename(href.text))
    end
  rescue *NETWORK_ERRORS => e
    raise Error, e.class.name
  end

  # o conteúdo de um arquivo pelo href que a busca devolveu
  def download(href)
    request = Net::HTTP::Get.new(href)
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    response = http.request(request)
    raise Error, "HTTP #{response.code} no arquivo" unless response.code == '200'
    raise Error, 'arquivo grande demais' if response.body.bytesize > MAX_BYTES

    response.body
  rescue *NETWORK_ERRORS => e
    raise Error, e.class.name
  end

  # o conteúdo de um arquivo pelo caminho na pasta do usuário ("/SERVIDOR/Almoxarifado$/Fotos/1_1.jpg"); nil se não existe
  def read(path)
    download("#{files_root}/#{encoded(path.delete_prefix('/'))}")
  rescue Error => e
    raise unless e.message.start_with?('HTTP 404')
  end

  private

  # o caminho dos arquivos usa o ID do usuário no Nextcloud, que pode não ser o login (conta criada por e-mail, LDAP):
  # pergunta ao próprio Nextcloud quem é o usuário da senha
  def user_id
    @user_id ||= begin
      request = Net::HTTP::Get.new("#{@base.path}/ocs/v2.php/cloud/user?format=json")
      request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
      request['OCS-APIRequest'] = 'true'
      response = http.request(request)
      raise Error, "HTTP #{response.code}" unless response.code == '200'

      JSON.parse(response.body).dig('ocs', 'data', 'id').presence || @settings.nextcloud_user
    rescue JSON::ParserError
      @settings.nextcloud_user
    end
  end

  def list_request(folder)
    request = Net::HTTP::Propfind.new("#{files_root}/#{encoded(folder.delete_prefix('/'))}/")
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    request['Depth'] = '1'
    request['Content-Type'] = 'text/xml; charset=utf-8'
    request.body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>'
    request
  end

  def search_request(folder, pattern)
    request = Outsider::Erp::NextcloudClient::SearchRequest.new("#{@base.path}/remote.php/dav/")
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    request['Content-Type'] = 'text/xml; charset=utf-8'
    # o escopo vai como caminho puro, como na documentação do Nextcloud ("Fiscal%24" não era achado como "Fiscal$")
    request.body = search_body("/files/#{user_id}#{folder}", pattern)
    request
  end

  def search_body(scope, pattern)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:searchrequest xmlns:d="DAV:">
        <d:basicsearch>
          <d:select><d:prop><d:displayname/><d:getlastmodified/></d:prop></d:select>
          <d:from><d:scope><d:href>#{CGI.escapeHTML(scope)}</d:href><d:depth>infinity</d:depth></d:scope></d:from>
          <d:where><d:like><d:prop><d:displayname/></d:prop><d:literal>#{CGI.escapeHTML(pattern)}</d:literal></d:like></d:where>
          <d:orderby/>
        </d:basicsearch>
      </d:searchrequest>
    XML
  end

  def http
    Net::HTTP.new(@base.host, @base.port).tap do |client|
      client.use_ssl = @base.scheme == 'https'
      client.open_timeout = TIMEOUT
      client.read_timeout = TIMEOUT
    end
  end
end
