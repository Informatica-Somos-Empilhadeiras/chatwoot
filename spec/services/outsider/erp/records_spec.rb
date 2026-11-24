require 'rails_helper'

# OUTSIDER: seção ERP (Outsider::Erp::Records): listas com todo o histórico lidas direto do banco do ERP, contagens e o
# detalhe com a corrente orçamento -> OS -> pedido -> notas (NF-e e NFS-e). O query_execute é simulado conforme a SQL recebida; aqui o que se
# confere é a SQL: só SELECT, só nos bancos das Configurações, valores escapados, nunca a coluna de senha.
RSpec.describe 'Outsider ERP records section' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:columns) do
    {
      'orcamento' => %w[codigoorcamento CodigoCliente orcamentoData Status total Vendedor OrdemServico CodigoIntegracaoMobile IDLogado Validade
                        DataStatus OrcamentoEmUtilizacao NomeUserEmUtilizacao DataEmUtilizacao Contato],
      'os' => %w[CodigoOS CodigoCliente DataEntrada Situacao Total Tecnico DataPrevisao DataEntrega NSerie Orcamento Pedido Defeitos
                 TipoAtendimento Vendedor],
      'pedido' => %w[CodigoPedido CodigoCliente PedidoData Vendedor total orcamento NotaFiscal fechado OS],
      'notafiscal' => %w[CodigoNF Emissao Status TotalNF Pedido TipoNota],
      'notafiscalservico' => %w[SeqNFSe Emissao Status TotalNF Pedido CodigoNFS CodigoRps],
      'clientes' => %w[CodigoCliente Nome Apelido CPF_CNPJ Cidade UF],
      'funcionarios' => %w[CodigoFuncionario Nome Senha Vendedor],
      'detalheorcamento' => %w[CodigoOrcamento CodigoItem CodigoProduto Quantidade PrecoUnitario TotalLinha],
      'produtos' => %w[CodigoProduto Descricao Tipo Unidade]
    }
  end
  let(:sqls) { [] }
  let(:quote_header) do
    { 'data' => '2026-11-10T03:00:00.000Z', 'status' => 'NEGOCIAÇÃO', 'total' => 1200.5, 'cliente_codigo' => 716, 'vendedor' => 6, 'os' => 310,
      'em_uso' => 0, 'contato' => ' Gilmar ' }
  end

  before do
    account.update!(internal_attributes: { 'outsider_erp' => {
                      'enabled' => true, 'companies' => %w[somosemp somosfilial], 'orders_enabled' => true, 'quotes_enabled' => true,
                      'user_erp_ids' => { user.id.to_s => '6' }
                    } })
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      sql = JSON.parse(request.body)['SQL_Execute']
      sqls << sql
      { status: 200, body: answer(sql).to_json }
    end
  end

  def answer(sql)
    return columns.fetch(sql[/LOWER\(TABLE_NAME\) = '(\w+)'/, 1], []).map { |name| { 'COLUMN_NAME' => name } } if sql.include?('information_schema')
    return dimension_rows if sql.include?(' AS dim, ')
    return facet_rows if sql.include?('COUNT(*) AS qtd')
    return page_rows if sql.start_with?('SELECT X.*')

    detail_answer(sql)
  end

  def facet_rows
    [
      { 'banco' => 'somosemp', 'status' => 'NEGOCIAÇÃO', 'pessoa_codigo' => 6, 'pessoa' => 'CRISTIANE', 'atrasada' => 0, 'qtd' => 3, 'soma' => 300 },
      { 'banco' => 'somosemp', 'status' => 'FECHADO', 'pessoa_codigo' => 11, 'pessoa' => 'ALICE', 'atrasada' => 0, 'qtd' => 5, 'soma' => '500.5' },
      { 'banco' => 'somosfilial', 'status' => 'PERDIDO', 'pessoa_codigo' => 6, 'pessoa' => 'CRISTIANE', 'atrasada' => 0, 'qtd' => 2, 'soma' => 20 }
    ]
  end

  def dimension_rows
    [{ 'dim' => 'atendimento', 'valor' => 'GARANTIA', 'nome' => nil, 'qtd' => 4 },
     { 'dim' => 'vendedor', 'valor' => 11, 'nome' => ' ALICE ', 'qtd' => 2 },
     { 'dim' => 'atendimento', 'valor' => 'ENTREGA TÉCNICA', 'nome' => nil, 'qtd' => 3 }]
  end

  def page_rows
    [{ 'banco' => 'somosemp', 'numero' => '4119', 'data' => '2026-11-19T22:00:00.000Z', 'status' => 'NEGOCIAÇÃO', 'total' => '64510.5',
       'cliente_codigo' => 716, 'cliente' => ' PRIMA  FOODS ', 'pessoa_codigo' => 6, 'pessoa' => 'CRISTIANE' }]
  end

  # o primeiro trecho de SQL encontrado decide a resposta (o cabeçalho do orçamento vem depois da consulta da corrente)
  def detail_answer(sql)
    {
      'FROM somosemp.orcamento O WHERE O.`codigoorcamento` = 4119 ORDER' => [{ 'numero' => 4119, 'os' => 310, 'status' => 'NEGOCIAÇÃO',
                                                                               'data' => '2026-11-10T03:00:00.000Z' }],
      'FROM somosemp.orcamento O WHERE O.`codigoorcamento` = 4119' => [quote_header],
      'FROM somosemp.os O WHERE' => [{ 'numero' => 310, 'status' => 'FECHADA', 'pedido' => 155, 'data' => '2026-11-12T03:00:00.000Z',
                                       'entrega' => '2026-11-15T03:00:00.000Z' }],
      'FROM somosemp.pedido O WHERE' => [{ 'numero' => 155, 'fechado' => 1, 'data' => '2026-11-16T03:00:00.000Z' }],
      'FROM somosemp.notafiscal O WHERE' => [{ 'numero' => 15_016, 'status' => 'IMPRESSA', 'pedido' => 155, 'tipo' => 0,
                                               'data' => '2026-11-17T03:00:00.000Z' }],
      'FROM somosemp.notafiscalservico O WHERE' => [{ 'numero' => 77, 'status' => 'IMPRESSA', 'pedido' => 155, 'nfse' => 2_027_001,
                                                      'data' => '2026-11-17T03:00:00.000Z' }],
      '.detalheorcamento D' => [{ 'codigo' => 491, 'descricao' => 'MOLA', 'tipo' => 0, 'quantidade' => 2, 'unitario' => 142, 'total' => 284 }]
    }.find { |fragment, _| sql.include?(fragment) }&.last || []
  end

  def lister(kind) = Outsider::Erp::Records::Lister.new(account, kind, user: user)
  def erp_sqls = sqls.grep_v(/information_schema/)

  describe 'lists' do
    it 'reads every configured bank in one UNION, with no date window, and never the password column' do
      result = lister('quotes').page({})

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include('FROM somosemp.orcamento O', 'FROM somosfilial.orcamento O', 'UNION ALL', 'LIMIT 50 OFFSET 0')
      expect(page).not_to match(/orcamentoData\W+>=|Senha/i)
      expect(erp_sqls).to all(start_with('SELECT '))
      expect(result[:items].first).to include('numero' => 4119, 'total' => 64_510.5, 'cliente' => 'PRIMA FOODS')
    end

    it 'counts views, banks and people with the other filters applied' do
      result = lister('quotes').page({ company: 'somosemp' })

      expect(result[:views].to_h { |view| [view[:key], view[:count]] }).to eq('all' => 8, 'negotiation' => 3, 'closed' => 5, 'lost' => 0, 'mine' => 3)
      expect(result[:companies]).to eq([{ value: 'somosemp', count: 8 }, { value: 'somosfilial', count: 2 }])
      expect(result[:total]).to eq(8)
      expect(result[:sum]).to eq(800.5)
    end

    it 'escapes the search and ignores a bank outside the settings' do
      lister('quotes').page({ q: "pri'ma 100%", company: 'outrocliente', per: 500, page: 3 })

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include("LIKE '%pri\\'ma%'", "LIKE '%100\\\\%%'", 'LIMIT 50 OFFSET 100')
      expect(page).not_to include('outrocliente')
    end

    it 'searches numbers by record number or CNPJ digits' do
      lister('quotes').page({ q: '12.345.678' })

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include('X.numero = 12345678', "LIKE '%12345678%'")
    end

    it 'filters by the contact clients and by my ERP code' do
      lister('quotes').page({ view: 'mine', clients: [['somosemp', 716], ['hacker', 1]] })

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include("(X.banco = 'somosemp' AND X.cliente_codigo IN (716))", 'X.pessoa_codigo = 6')
      expect(page).not_to include('hacker')
    end

    it 'marks late service orders by the forecast date and leaves closed ones out of the open view' do
      lister('orders').page({ view: 'open' })

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include('FROM somosemp.os O', "NOT IN ('FECHADA', 'CANCELADA', 'PERDIDA')")
      expect(erp_sqls.find { |sql| sql.include?('COUNT(*)') }).to include('X.previsao < CURDATE()')
    end

    it 'filters service orders by attendance type and seller, counts each one without its own filter, and sorts blanks last' do
      result = lister('orders').page({ view: 'all', atendimento: " garantia'", vendedor: '11', sort: 'atendimento', direction: 'desc' })

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include("NULLIF(TRIM(X.atendimento), '') = 'garantia\\''", 'NULLIF(X.vendedor_codigo, 0) = 11',
                              'LEFT JOIN somosemp.funcionarios V ON V.`CodigoFuncionario` = O.`Vendedor`', 'V.`Nome` AS vendedor',
                              "ORDER BY (X.atendimento IS NULL OR X.atendimento = '') ASC, X.atendimento DESC")
      attendance, seller = erp_sqls.find { |sql| sql.include?(' AS dim, ') }.split("UNION ALL SELECT 'vendedor' AS dim")
      expect(attendance).to include('NULLIF(X.vendedor_codigo, 0) = 11')
      expect(attendance).not_to include("= 'garantia")
      expect(seller).to include("= 'garantia\\''")
      expect(seller).not_to include('NULLIF(X.vendedor_codigo, 0) = 11')
      expect(result[:dimensions]).to eq(atendimento: [{ value: 'ENTREGA TÉCNICA', name: nil, count: 3 }, { value: 'GARANTIA', name: nil, count: 4 }],
                                        vendedor: [{ value: 11, name: 'ALICE', count: 2 }])
    end

    it 'only sorts by what the list knows and ignores filters the kind does not have' do
      lister('quotes').page({ sort: 'X.total; DROP', atendimento: 'GARANTIA' })

      page = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }
      expect(page).to include('ORDER BY X.data DESC')
      expect(page).not_to include('GARANTIA')
      expect(erp_sqls.grep(/ AS dim, /)).to be_empty
    end

    it 'derives the sales order status when the bank has no status column' do
      lister('sales').page({})

      expect(erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }).to include("WHEN IFNULL(O.`NotaFiscal`, 0) > 0 THEN 'FATURADO'")
    end
  end

  describe 'detail' do
    let(:detail) { Outsider::Erp::Records::Detail.new(account, 'quotes').build('somosemp', '4119') }

    it 'builds the header, items and the quote -> OS -> pedido -> notes chain' do
      expect(detail['header']).to include('status' => 'NEGOCIAÇÃO', 'contato' => 'Gilmar')
      expect(detail['itens']).to eq([{ 'codigo' => 491, 'descricao' => 'MOLA', 'servico' => false, 'unidade' => '', 'quantidade' => 2.0,
                                       'unitario' => 142.0, 'desconto' => 0.0, 'total' => 284.0 }])
      expect(detail['chain'].map { |node| [node['kind'], node['numero'], node['status'], node['current']] })
        .to eq([['quotes', 4119, 'NEGOCIAÇÃO', true], ['orders', 310, 'FECHADA', false], ['sales', 155, 'FECHADO', false],
                ['invoices', 15_016, 'IMPRESSA', false], ['service_invoices', 77, 'IMPRESSA', false]])
      expect(detail['chain'].last).to include('rotulo' => '2027001', 'pedido' => 155)
      expect(detail['edit']).to eq('allowed' => true, 'in_use_by' => nil)
    end

    it 'finds the pedido through the OS and the notes through the pedido, and shows them on the timeline' do
      expect(detail['timeline'].pluck('type').first(3)).to eq(%w[created created delivered])
      expect(detail['timeline'].pluck('type').last(3)).to eq(%w[created invoiced invoiced])
      expect(erp_sqls.find { |sql| sql.include?('FROM somosemp.pedido O WHERE O.`orcamento`') }).to include('O.`OS` IN (310)')
      expect(erp_sqls.find { |sql| sql.include?('FROM somosemp.notafiscal O WHERE') }).to include('O.`Pedido` IN (155)')
    end

    it 'blocks editing while the quote is open in the desktop app, but not for an old mark' do
      quote_header.merge!('em_uso' => 1, 'em_uso_por' => 'CRISTIANE', 'em_uso_desde' => 10.minutes.ago.iso8601)
      expect(detail['edit']).to eq('allowed' => false, 'in_use_by' => 'CRISTIANE')

      quote_header['em_uso_desde'] = 3.days.ago.iso8601
      expect(Outsider::Erp::Records::Detail.in_use?(quote_header)).to be(false)
    end

    it 'blocks editing outside NEGOCIAÇÃO' do
      quote_header['status'] = 'FECHADO'
      expect(detail['edit']['allowed']).to be(false)
    end

    it 'refuses a bank outside the settings and reports a missing record' do
      expect { Outsider::Erp::Records::Detail.new(account, 'quotes').build('outrocliente', 1) }.to raise_error(ArgumentError)
      expect { Outsider::Erp::Records::Detail.new(account, 'quotes').build('somosemp', 1) }.to raise_error(Outsider::Erp::Records::Detail::NotFound)
      expect(erp_sqls).to all(start_with('SELECT '))
      expect(sqls.join).not_to include('outrocliente')
    end
  end
end
