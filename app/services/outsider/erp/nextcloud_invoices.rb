# OUTSIDER: o PDF oficial de uma nota fiscal espelhado do Nextcloud da Somos, onde o escritório guarda as notas como
# "<número> (<CFOP>) <cliente>.pdf" na pasta de cada unidade (Configurações do ERP). Acha o arquivo pelo número da nota
# com a busca do próprio Nextcloud (WebDAV SEARCH, nas subpastas também) e baixa na hora: nada fica guardado no chat.
# Com mais de um arquivo para o mesmo número, vale o mais recente.
class Outsider::Erp::NextcloudInvoices
  class NotFound < StandardError; end
  class Error < StandardError; end

  TIMEOUT = 20
  MAX_BYTES = 20.megabytes

  def initialize(account)
    @settings = Outsider::Erp::Settings.new(account)
    @base = URI.parse(@settings.nextcloud_url)
  end

  # { 'filename', 'content' }
  def fetch(company, number)
    number = Integer(number.to_s, 10).to_s
    folder = @settings.nextcloud_folders[company] || raise(NotFound)
    href = newest(search(folder, number), folder, number) || raise(NotFound)
    { 'filename' => File.basename(URI.decode_uri_component(href)), 'content' => download(href) }
  end

  private

  def files_root = "#{@base.path}/remote.php/dav/files/#{ERB::Util.url_encode(@settings.nextcloud_user)}"

  def encoded(path) = path.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')

  def search(folder, number)
    response = http.request(search_request(folder, number))
    raise Error, "HTTP #{response.code}" unless response.code == '207'

    Nokogiri::XML(response.body).remove_namespaces!.xpath('//response').map do |node|
      [node.at_xpath('href').text, node.at_xpath('.//getlastmodified')&.text.to_s]
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    raise Error, e.class.name
  end

  def search_request(folder, number)
    request = Outsider::Erp::NextcloudInvoices::SearchRequest.new("#{@base.path}/remote.php/dav/")
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    request['Content-Type'] = 'text/xml; charset=utf-8'
    request.body = search_body("/files/#{ERB::Util.url_encode(@settings.nextcloud_user)}#{encoded(folder)}", "#{number} %")
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

  # só PDF desta nota ("3594 (6102) ..." serve, "35940 ..." não) e dentro da pasta da unidade (comparado decodificado:
  # o Nextcloud codifica o caminho do jeito dele)
  def newest(results, folder, number)
    prefix = URI.decode_uri_component("#{files_root}#{encoded(folder)}/")
    name = /\A#{number}[ (].*\.pdf\z/i
    results.select { |href, _| this_note?(URI.decode_uri_component(href), prefix, name) }.max_by { |_, modified| modified_at(modified) }&.first
  end

  def this_note?(path, prefix, name)
    path.start_with?(prefix) && path.exclude?('/../') && File.basename(path).match?(name)
  end

  def modified_at(text)
    Time.httpdate(text).to_i
  rescue ArgumentError
    0
  end

  def download(href)
    request = Net::HTTP::Get.new(href)
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    response = http.request(request)
    raise Error, "HTTP #{response.code}" unless response.code == '200'
    raise Error, 'arquivo grande demais' if response.body.bytesize > MAX_BYTES

    response.body
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    raise Error, e.class.name
  end

  def http
    Net::HTTP.new(@base.host, @base.port).tap do |client|
      client.use_ssl = @base.scheme == 'https'
      client.open_timeout = TIMEOUT
      client.read_timeout = TIMEOUT
    end
  end
end
