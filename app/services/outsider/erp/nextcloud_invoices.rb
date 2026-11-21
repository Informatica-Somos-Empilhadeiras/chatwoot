# OUTSIDER: o PDF oficial de uma nota fiscal espelhado do Nextcloud da Somos. O Fiscal guarda as notas de todas as
# empresas em subpastas que ele organiza: NF-e como "5868 (5405) CLIENTE EXEMPLO SA - 2083.pdf" (número, CFOP, cliente
# e pedido interno) e NFS-e como "841-NFS CLIENTE EXEMPLO SA - 2083.PDF" (número da prefeitura, cliente e pedido). A
# busca parte da pasta raiz das Configurações (a do Fiscal), com a busca do próprio Nextcloud (WebDAV SEARCH, em todas
# as subpastas). A mesma numeração existe em outras empresas, então o arquivo só vale se o CFOP (NF-e) bater com a nota
# no ERP e o pedido ou o cliente também; o pedido pesa mais, porque o nome do cliente pode vir abreviado ("CLIENTE AF
# 123456"). Na dúvida não mostra: nunca a nota de outra empresa. Baixa na hora e repassa o arquivo como está.
class Outsider::Erp::NextcloudInvoices
  class NotFound < StandardError; end
  Error = Outsider::Erp::NextcloudClient::Error

  S = Outsider::Erp::Sql
  NAME_CHARS = 20
  # por tipo de nota: tabela e chave no ERP, a coluna do número que vai no nome do arquivo, o cliente, o CFOP, o texto da
  # busca e o começo do nome (o resto é o cliente e o pedido opcional no fim, NAME_END)
  KINDS = {
    'invoices' => {
      table: 'notafiscal', key: 'CodigoNF', number: 'N.CodigoNF', client: 'N.CodigoCliente', cfop: 'N.CFOP',
      search: ->(number) { "#{number} %" }, start: ->(number) { /\A#{number}(?=[ (])\s*(?:\((\d{4})\))?/i }
    },
    # o destinatário só é cliente com isCliente ligado (senão é fornecedor, sem cadastro em clientes)
    'service_invoices' => {
      table: 'notafiscalservico', key: 'SeqNFSe', number: 'N.CodigoNFS', client: 'N.CodigoDestinatario AND N.isCliente <> 0',
      cfop: 'NULL', search: ->(number) { "#{number}%" }, start: ->(number) { /\A#{number}\s*-\s*NFS(?:-?e)?()/i }
    }
  }.freeze
  NAME_END = /\s*(.*?)(?:\s+-\s+(\d+))?\s*\.pdf\z/i

  def initialize(account)
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
    @nextcloud = Outsider::Erp::NextcloudClient.new(@settings)
  end

  # kind: invoices (NF-e) ou service_invoices (NFS-e); number: a chave da nota no ERP. { 'filename', 'content' }
  def fetch(company, number, kind)
    note = summary(company, number, kind)
    found = @nextcloud.search(@settings.nextcloud_folder, @kind[:search].call(note['numero']))
    href = pick(this_number(found, note['numero']), note) || raise(NotFound)
    { 'filename' => File.basename(URI.decode_uri_component(href)), 'content' => @nextcloud.download(href) }
  end

  # a nota no ERP: { 'numero' (o que vai no nome do arquivo), 'cfop', 'pedido', 'cliente' (nome) }
  def summary(company, number, kind)
    raise ArgumentError, 'company' unless @settings.companies.include?(company)

    @kind = KINDS.fetch(kind)
    note = note(company, Integer(number.to_s, 10))
    # NFS-e sem o número da prefeitura ainda não foi emitida
    raise NotFound unless note['numero'].to_i.positive?

    note.merge('numero' => note['numero'].to_i)
  end

  private

  # número do arquivo, CFOP, cliente e pedido da nota no ERP, para separar das notas de mesmo número das outras empresas
  def note(company, number)
    db = S.ident(company)
    name = @schema.pick(company, 'clientes', %w[Nome RazaoSocial NomeCliente Razao])
    code = @schema.pick(company, 'clientes', %w[CodigoCliente Codigo])
    client = name && code ? "C.#{S.column(name)}" : 'NULL'
    join = name && code ? " LEFT JOIN #{db}.clientes C ON C.#{S.column(code)} = #{@kind[:client]}" : ''
    sql = "SELECT #{@kind[:number]} AS numero, #{@kind[:cfop]} AS cfop, N.Pedido AS pedido, #{client} AS cliente " \
          "FROM #{db}.#{@kind[:table]} N#{join} WHERE N.#{@kind[:key]} = #{S.int(number)}"
    @client.query_execute(sql).grep(Hash).first || raise(NotFound)
  end

  # { href, modified, cfop, client, order } dos PDFs desta nota dentro da raiz ("3594 (6102) ..." serve, "35940 ..." e
  # "3594-NFS ..." não, para a NF-e 3594)
  def this_number(results, number)
    prefix = URI.decode_uri_component("#{@nextcloud.files_root}#{@nextcloud.encoded(@settings.nextcloud_folder)}/")
    name_pattern = /#{@kind[:start].call(number)}#{NAME_END}/
    results.filter_map do |href, modified|
      path = URI.decode_uri_component(href)
      next unless path.start_with?(prefix) && path.exclude?('/../') && (match = File.basename(path).match(name_pattern))

      { href: href, modified: modified, cfop: match[1], client: match[2], order: match[3] }
    end
  end

  # o pedido pesa mais que o cliente; empate fica com o mais recente (a mesma nota guardada em duas pastas). Sem pedido
  # nem cliente no ERP, só vale se houver um arquivo só
  def pick(files, note)
    candidates = files.select { |file| same_cfop?(file[:cfop], note['cfop']) }
    chosen = buyer?(note) ? best_scored(candidates, note) : only(candidates)
    chosen.max_by { |file| modified_at(file[:modified]) }&.dig(:href)
  end

  def only(files) = files.one? ? files : []

  def buyer?(note) = note['cliente'].present? || note['pedido'].to_i.positive?

  def best_scored(candidates, note)
    scored = candidates.group_by { |file| score(file, note) }.except(0)
    scored.empty? ? [] : scored[scored.keys.max]
  end

  def score(file, note)
    (same_order?(file[:order], note['pedido']) ? 2 : 0) + (same_client?(file[:client], note['cliente']) ? 1 : 0)
  end

  # o pedido interno no fim do nome ("... - 2083")
  def same_order?(file_order, erp_order) = file_order.present? && file_order.to_i.positive? && file_order.to_i == erp_order.to_i

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

  def modified_at(text)
    Time.httpdate(text).to_i
  rescue ArgumentError
    0
  end
end
