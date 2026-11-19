# OUTSIDER: lê do ERP tudo que o PDF de um orçamento precisa, no formato do relatório do Mais Prático (orçamento 3309):
# cabeçalho, cliente, linhas com NCM/CST/ICMS, condições de pagamento, Demais Condições, totais e observações. Serve
# para qualquer orçamento da unidade, feito no chat ou no próprio ERP. Só leitura, filtrado pelo banco e pelo número.
# Devolve o hash que o Outsider::Erp::QuotePdf desenha (o mesmo que o Outsider::Erp::BudgetPreview monta do rascunho).
class Outsider::Erp::QuoteReport
  S = Outsider::Erp::Sql
  HEADER = {
    'cliente' => %w[CodigoCliente], 'data' => %w[orcamentoData], 'pagamento' => %w[FormaPagto], 'vendedor' => %w[Vendedor],
    'contato' => %w[Contato], 'telefone' => %w[Telefone], 'observacoes' => %w[Observacoes], 'status' => %w[Status],
    'prazo_entrega' => %w[PrazoEntrega], 'icms_txt' => %w[ICMS], 'validade' => %w[Validade], 'desc_frete' => %w[descFrete],
    'reajuste' => %w[Reajuste], 'ipi_txt' => %w[IPI], 'garantia' => %w[PrazoGarantia], 'armazenagem' => %w[TaxaArmazenagem],
    'cancelamento' => %w[TaxaCancelamento], 'cubagem' => %w[VolumeM3], 'volumes' => %w[quantidade],
    'vr_ipi' => %w[VRIPI], 'outras' => %w[outrasDespesas], 'seguro' => %w[vrSeguro], 'base_st' => %w[basest], 'vr_st' => %w[vrST],
    'base_icms' => %w[baseICMS], 'vr_icms' => %w[vrICMS], 'desconto' => %w[descontototal], 'acrescimo' => %w[acrescimo],
    'frete' => %w[Frete], 'total' => %w[total]
  }.freeze
  LINES = {
    'quantidade' => %w[Quantidade], 'unitario' => %w[PrecoUnitario], 'desconto_un' => %w[Desconto], 'total' => %w[TotalLinha],
    'ncm' => %w[ClasFiscal], 'cst' => %w[SitTrib], 'icms' => %w[AliqICMS], 'vr_icms' => %w[VrICMS]
  }.freeze
  # rótulo no PDF => campo do cabeçalho (Demais Condições, na ordem do relatório do Mais Prático)
  CONDITIONS = [['Prazo de Entrega', 'prazo_entrega'], ['ICMS', 'icms_txt'], ['Validade', 'validade'], ['Desc. Frete', 'desc_frete'],
                ['Reajuste', 'reajuste'], ['IPI', 'ipi_txt'], ['Prazo de Garantia', 'garantia'], ['Taxa de Armazenagem', 'armazenagem'],
                ['Taxa de Cancelamento', 'cancelamento']].freeze

  class NotFound < StandardError; end

  def initialize(account)
    @account = account
    @client = Outsider::Erp::Client.new(Outsider::Erp::Settings.new(account))
    @schema = Outsider::Erp::Schema.new(account, client: @client)
  end

  def build(company, number)
    header = header(company, number)
    lines = lines(company, number)
    {
      'numero' => number.to_i, 'data' => header['data'].to_s.first(10), 'company' => company, 'previa' => false,
      'itens' => lines, 'pagamento' => header['pagamento'].to_s.strip, 'condicoes' => conditions(header),
      'totais' => totals(header, lines), 'total' => header['total'].to_f.round(2), 'status' => header['status'],
      'observacoes' => header['observacoes'].to_s.strip
    }.merge(people(company, header))
  end

  # cabeçalho cru do orçamento (as chaves do HEADER); também serve para o "Copiar" de um orçamento feito no ERP
  def header(company, number)
    sql = "SELECT #{@schema.select_list(company, 'orcamento', 'O', HEADER)} FROM #{S.ident(company)}.orcamento O " \
          "WHERE O.codigoorcamento = #{S.int(number)}"
    @client.query_execute(sql).grep(Hash).first || raise(NotFound, number.to_s)
  end

  def lines(company, number)
    description = @schema.pick(company, 'produtos', %w[Descricao DescricaoProduto Nome])
    unit = @schema.pick(company, 'produtos', %w[Unidade])
    sql = "SELECT D.CodigoProduto AS codigo, #{@schema.select_list(company, 'detalheorcamento', 'D', LINES)}, " \
          "#{description ? "P.#{S.column(description)}" : 'NULL'} AS descricao, #{unit ? "P.#{S.column(unit)}" : 'NULL'} AS unidade " \
          "FROM #{S.ident(company)}.detalheorcamento D LEFT JOIN #{S.ident(company)}.produtos P ON P.CodigoProduto = D.CodigoProduto " \
          "WHERE D.CodigoOrcamento = #{S.int(number)} ORDER BY D.CodigoItem"
    @client.query_execute(sql).grep(Hash).map { |row| line(row) }
  end

  private

  # emitente, cliente (com o A/C e o telefone do orçamento) e vendedor
  def people(company, header)
    {
      'emitente' => Outsider::Erp::Emitter.new(@account, client: @client).data_for(company),
      'cliente' => Outsider::Erp::CustomerRecord.new(@account, client: @client).find(company, header['cliente'])
                                                .merge('contato' => header['contato'], 'fone_contato' => header['telefone']),
      'vendedor' => Outsider::Erp::SellerName.new(@account, client: @client).for_code(company, header['vendedor'])
    }
  end

  # o ERP guarda o desconto por unidade; o relatório mostra o da linha
  def line(row)
    quantity = row['quantidade'].to_f
    text = %w[unidade ncm cst].index_with { |key| row[key].to_s.strip }
    {
      'codigo' => row['codigo'].to_i, 'descricao' => row['descricao'].to_s.squish, 'quantidade' => quantity,
      'icms' => row['icms']&.to_f, 'vr_icms' => row['vr_icms']&.to_f, 'desconto' => (row['desconto_un'].to_f * quantity).round(2),
      'unitario' => row['unitario'].to_f, 'total' => row['total'].to_f
    }.merge(text)
  end

  def conditions(header)
    CONDITIONS.map { |label, key| [label, header[key].to_s.strip] } +
      [['Cubagem', "#{number(header['cubagem'])} m³"], ['Quantidade de Volumes', number(header['volumes'])]]
  end

  # Sub-Total = soma das linhas (peças e serviços), como no relatório do Mais Prático
  def totals(header, lines)
    [['Sub-Total', lines.sum { |row| row['total'] }], ['Vr. IPI', header['vr_ipi']], ['Outras Despesas', header['outras']],
     ['Vr. Seguro', header['seguro']], ['Base ST', header['base_st']], ['Valor ST', header['vr_st']],
     ['Base ICMS', header['base_icms']], ['Vr. ICMS', header['vr_icms']], ['Desconto', header['desconto']],
     ['Acréscimo', header['acrescimo']], ['Frete', header['frete']]].map { |label, value| [label, value.to_f.round(2)] }
  end

  def number(value)
    ActiveSupport::NumberHelper.number_to_rounded(value.to_f, precision: 2, separator: ',', delimiter: '.')
  end
end
