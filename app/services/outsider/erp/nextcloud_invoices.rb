# OUTSIDER: o PDF oficial de uma nota fiscal espelhado do Nextcloud da Somos. O Fiscal guarda as notas de todas as
# empresas como "<número> (<CFOP>) <cliente>.pdf" em subpastas que ele organiza; a busca parte da pasta raiz das
# Configurações (a do Fiscal) e usa a busca do próprio Nextcloud (WebDAV SEARCH, em todas as subpastas). A mesma
# numeração existe em outras empresas, então o arquivo só vale se o CFOP e o cliente baterem com a nota no ERP (sem
# cliente no ERP, só um arquivo com o mesmo CFOP serve). Na dúvida não mostra: nunca a nota de outra empresa. Baixa na
# hora: nada fica guardado no chat.
class Outsider::Erp::NextcloudInvoices
  class NotFound < StandardError; end
  class Error < StandardError; end

  S = Outsider::Erp::Sql
  TIMEOUT = 20
  MAX_BYTES = 20.megabytes
  FILE_NAME = /\A\d+\s*(?:\((\d{4})\))?\s*(.*?)\s*\.pdf\z/i
  NAME_CHARS = 20

  def initialize(account)
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
    @base = URI.parse(@settings.nextcloud_url)
  end

  # { 'filename', 'content' }
  def fetch(company, number)
    raise ArgumentError, 'company' unless @settings.companies.include?(company)

    number = Integer(number.to_s, 10).to_s
    href = pick(this_number(search(number), number), note(company, number)) || raise(NotFound)
    { 'filename' => File.basename(URI.decode_uri_component(href)), 'content' => download(href) }
  end

  private

  # CFOP e cliente da nota no ERP, para separar das notas de mesmo número das outras empresas
  def note(company, number)
    db = S.ident(company)
    name = @schema.pick(company, 'clientes', %w[Nome RazaoSocial NomeCliente Razao])
    code = @schema.pick(company, 'clientes', %w[CodigoCliente Codigo])
    client = name && code ? "C.#{S.column(name)}" : 'NULL'
    join = name && code ? " LEFT JOIN #{db}.clientes C ON C.#{S.column(code)} = N.CodigoCliente" : ''
    sql = "SELECT N.CFOP AS cfop, #{client} AS cliente FROM #{db}.notafiscal N#{join} WHERE N.CodigoNF = #{S.int(number)}"
    @client.query_execute(sql).grep(Hash).first || raise(NotFound)
  end

  # [[href, modificado, cfop, cliente]] dos PDFs desta nota ("3594 (6102) ..." serve, "35940 ..." não) dentro da raiz
  def this_number(results, number)
    prefix = URI.decode_uri_component("#{files_root}#{encoded(@settings.nextcloud_folder)}/")
    results.filter_map do |href, modified|
      path = URI.decode_uri_component(href)
      name = File.basename(path)
      next unless path.start_with?(prefix) && path.exclude?('/../') && name.match?(/\A#{number}[ (]/) && (match = name.match(FILE_NAME))

      [href, modified, match[1], match[2]]
    end
  end

  def pick(files, note)
    same_cfop = files.select { |_, _, file_cfop| same_cfop?(file_cfop, note['cfop']) }
    chosen = if note['cliente'].present?
               same_cfop.select { |*, file_client| same_client?(file_client, note['cliente']) }
             else
               same_cfop.one? ? same_cfop : []
             end
    chosen.max_by { |_, modified| modified_at(modified) }&.first
  end

  # arquivo sem CFOP no nome ou nota sem CFOP no ERP não descartam
  def same_cfop?(file_cfop, erp_cfop)
    erp_cfop = erp_cfop.to_s.gsub(/\D/, '')
    file_cfop.blank? || erp_cfop.blank? || file_cfop == erp_cfop
  end

  # o nome no arquivo pode vir abreviado ou sem acento: compara o começo, só letras e números
  def same_client?(file_client, erp_client)
    first, second = [file_client, erp_client].map { |text| I18n.transliterate(text.to_s).upcase.gsub(/[^A-Z0-9]/, '') }
    size = [first.size, second.size, NAME_CHARS].min
    size >= 5 && first.first(size) == second.first(size)
  end

  def files_root = "#{@base.path}/remote.php/dav/files/#{ERB::Util.url_encode(user_id)}"

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

  def encoded(path) = path.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')

  def search(number)
    response = http.request(search_request(number))
    raise Error, "HTTP #{response.code}" unless response.code == '207'

    Nokogiri::XML(response.body).remove_namespaces!.xpath('//response').map do |node|
      [node.at_xpath('href').text, node.at_xpath('.//getlastmodified')&.text.to_s]
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    raise Error, e.class.name
  end

  def search_request(number)
    request = Outsider::Erp::NextcloudInvoices::SearchRequest.new("#{@base.path}/remote.php/dav/")
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    request['Content-Type'] = 'text/xml; charset=utf-8'
    # o escopo vai como caminho puro, como na documentação do Nextcloud ("Fiscal%24" não era achado como "Fiscal$")
    scope = "/files/#{user_id}#{@settings.nextcloud_folder}"
    request.body = search_body(scope, "#{number} %")
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

  def modified_at(text)
    Time.httpdate(text).to_i
  rescue ArgumentError
    0
  end

  def download(href)
    request = Net::HTTP::Get.new(href)
    request.basic_auth(@settings.nextcloud_user, @settings.nextcloud_password)
    response = http.request(request)
    raise Error, "HTTP #{response.code} no arquivo" unless response.code == '200'
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
