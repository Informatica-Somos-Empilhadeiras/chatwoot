# OUTSIDER: leituras do ERP para o vínculo técnico/OS do pedido de venda (Outsider::Erp::SaleAttributor) e o relatório
# de desempenho dos técnicos (Outsider::Erp::TechnicianReport): pedidos, OS, as notas fiscais (NF-e e NFS-e) de cada
# pedido e os nomes de funcionários e clientes, sempre em lote e no banco de uma unidade. Só leitura; as colunas são
# conferidas no information_schema (Outsider::Erp::Schema).
class Outsider::Erp::SaleLookup
  S = Outsider::Erp::Sql
  BATCH = 500
  SALE = { 'numero' => %w[CodigoPedido], 'data' => %w[PedidoData], 'total' => %w[total Total], 'vendedor' => %w[Vendedor],
           'cliente' => %w[CodigoCliente], 'orcamento' => %w[orcamento Orcamento], 'os' => %w[OS] }.freeze
  ORDER = { 'numero' => %w[CodigoOS], 'data' => %w[DataEntrada], 'situacao' => %w[Situacao], 'total' => %w[Total],
            'tecnico' => %w[Tecnico], 'vendedor' => %w[Vendedor], 'cliente' => %w[CodigoCliente], 'orcamento' => %w[Orcamento],
            'atendimento' => %w[TipoAtendimento] }.freeze
  # notas de saída que valem como faturamento: as canceladas, inutilizadas e denegadas não contam
  NOTES = {
    'invoices' => { table: 'notafiscal', map: { 'numero' => %w[CodigoNF], 'data' => %w[Emissao], 'status' => %w[Status],
                                                'total' => %w[TotalNF total], 'pedido' => %w[Pedido], 'tipo' => %w[TipoNota] } },
    'service_invoices' => { table: 'notafiscalservico', map: { 'numero' => %w[SeqNFSe], 'data' => %w[Emissao], 'status' => %w[Status],
                                                               'total' => %w[TotalNF Total], 'pedido' => %w[Pedido], 'rotulo' => %w[CodigoNFS] } }
  }.freeze
  NOT_BILLED = /CANCEL|INUTIL|DENEG|REJEIT/i

  def initialize(account, client: nil)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
  end

  attr_reader :client

  def sales(company, numbers) = by_number(company, 'pedido', SALE, numbers)
  def orders(company, numbers) = by_number(company, 'os', ORDER, numbers)

  # OS ligadas ao pedido no próprio ERP (pedido.OS e as OS do mesmo orçamento), para sugerir
  def linked_orders(company, sale)
    conditions = []
    conditions << "X.numero_col = #{S.int(sale['os'])}" if sale['os'].to_i.positive?
    conditions << "X.orcamento_col = #{S.int(sale['orcamento'])}" if sale['orcamento'].to_i.positive?
    conditions.empty? ? [] : rows(company, 'os', ORDER, conditions.join(' OR '), limit: 10)
  end

  # notas de saída válidas dos pedidos: { pedido => [{ kind, numero, data, total, rotulo }] }
  def notes_for(company, sale_numbers)
    ids = clean(sale_numbers)
    return {} if ids.empty?

    notes = NOTES.flat_map do |kind, spec|
      found = ids.each_slice(BATCH).flat_map { |slice| rows(company, spec[:table], spec[:map], "X.pedido_col IN (#{slice.join(', ')})") }
      found.select { |row| billed?(row) }.map { |row| row.merge('kind' => kind) }
    end
    notes.group_by { |row| row['pedido'].to_i }
  end

  # notas de saída válidas emitidas no período (data da nota), com pedido: a base do relatório
  def notes_between(company, from, to)
    NOTES.flat_map do |kind, spec|
      condition = "X.data_col >= #{S.str(from.to_s)} AND X.data_col < #{S.str((to + 1).to_s)} AND IFNULL(X.pedido_col, 0) > 0"
      rows(company, spec[:table], spec[:map], condition, limit: 20_000).select { |row| billed?(row) }.map { |row| row.merge('kind' => kind) }
    end
  end

  # { código => nome } dos funcionários do ERP (vendedores e técnicos)
  def people(company, codes)
    names(company, 'funcionarios', Outsider::Erp::SellerName::CODE, Outsider::Erp::SellerName::NAME, codes)
  end

  def clients(company, codes) = names(company, 'clientes', %w[CodigoCliente Codigo], %w[Nome RazaoSocial NomeCliente Razao], codes)

  private

  def billed?(row) = row['tipo'].to_i != 1 && !row['status'].to_s.match?(NOT_BILLED)

  def clean(values) = Array(values).map(&:to_i).select(&:positive?).uniq

  def by_number(company, table, mapping, numbers)
    clean(numbers).each_slice(BATCH).flat_map { |slice| rows(company, table, mapping, "X.numero_col IN (#{slice.join(', ')})") }
                  .index_by { |row| row['numero'].to_i }
  end

  # SELECT com as colunas que existem; "X.<chave>_col" na condição vira a coluna real (ou NULL)
  def rows(company, table, mapping, condition, limit: BATCH)
    picked = mapping.transform_values { |candidates| @schema.pick(company, table, candidates) }
    return [] unless picked['numero']

    where = condition.gsub(/\bX\.(\w+)_col\b/) { picked[Regexp.last_match(1)] ? "X.#{S.column(picked[Regexp.last_match(1)])}" : 'NULL' }
    sql = "SELECT #{@schema.select_list(company, table, 'X', mapping)} FROM #{S.ident(company)}.#{S.ident(table)} X " \
          "WHERE #{where} LIMIT #{limit.to_i}"
    @client.query_execute(sql, read_timeout: 60).grep(Hash)
  end

  def names(company, table, code_candidates, name_candidates, codes)
    ids = clean(codes)
    code = @schema.pick(company, table, code_candidates)
    name = @schema.pick(company, table, name_candidates)
    return {} if ids.empty? || code.nil? || name.nil?

    found = ids.each_slice(BATCH).flat_map do |slice|
      @client.query_execute("SELECT T.#{S.column(code)} AS codigo, T.#{S.column(name)} AS nome FROM #{S.ident(company)}.#{S.ident(table)} T " \
                            "WHERE T.#{S.column(code)} IN (#{slice.join(', ')})").grep(Hash)
    end
    found.to_h { |row| [row['codigo'].to_i, row['nome'].to_s.squish] }
  end
end
