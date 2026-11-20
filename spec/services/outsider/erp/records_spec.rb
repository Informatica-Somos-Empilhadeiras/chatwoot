require 'rails_helper'

# OUTSIDER: seção ERP (Outsider::Erp::Records): listas com todo o histórico lidas direto do banco do ERP, contagens e o
# detalhe com a corrente orçamento -> OS -> pedido. O query_execute é simulado conforme a SQL recebida; aqui o que se
# confere é a SQL: só SELECT, só nos bancos das Configurações, valores escapados, nunca a coluna de senha.
RSpec.describe 'Outsider ERP records section' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:columns) do
    {
      'orcamento' => %w[codigoorcamento CodigoCliente orcamentoData Status total Vendedor OrdemServico CodigoIntegracaoMobile IDLogado Validade
                        DataStatus OrcamentoEmUtilizacao NomeUserEmUtilizacao DataEmUtilizacao Contato],
      'os' => %w[CodigoOS CodigoCliente DataEntrada Situacao Total Tecnico DataPrevisao DataEntrega NSerie Orcamento Pedido Defeitos],
      'pedido' => %w[CodigoPedido CodigoCliente PedidoData Vendedor total orcamento NotaFiscal fechado],
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

  def page_rows
    [{ 'banco' => 'somosemp', 'numero' => '4119', 'data' => '2026-11-19T22:00:00.000Z', 'status' => 'NEGOCIAÇÃO', 'total' => '64510.5',
       'cliente_codigo' => 716, 'cliente' => ' PRIMA  FOODS ', 'pessoa_codigo' => 6, 'pessoa' => 'CRISTIANE' }]
  end

  def detail_answer(sql)
    if sql.include?('FROM somosemp.orcamento O WHERE O.`codigoorcamento` = 4119 ORDER')
      [{ 'numero' => 4119, 'os' => 310, 'status' => 'NEGOCIAÇÃO', 'data' => '2026-11-10T03:00:00.000Z' }]
    elsif sql.include?('FROM somosemp.orcamento O WHERE O.`codigoorcamento` = 4119') then [quote_header]
    elsif sql.include?('FROM somosemp.os O WHERE')
      [{ 'numero' => 310, 'status' => 'FECHADA', 'pedido' => 155, 'data' => '2026-11-12T03:00:00.000Z', 'entrega' => '2026-11-15T03:00:00.000Z' }]
    elsif sql.include?('FROM somosemp.pedido O WHERE') then [{ 'numero' => 155, 'nota' => 15_016, 'data' => '2026-11-16T03:00:00.000Z' }]
    elsif sql.include?('.detalheorcamento D') then [{ 'codigo' => 491, 'descricao' => 'MOLA', 'tipo' => 0, 'quantidade' => 2, 'unitario' => 142,
                                                      'total' => 284 }]
    else
      []
    end
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

    it 'derives the sales order status when the bank has no status column' do
      lister('sales').page({})

      expect(erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }).to include("WHEN IFNULL(O.`NotaFiscal`, 0) > 0 THEN 'FATURADO'")
    end
  end

  describe 'detail' do
    let(:detail) { Outsider::Erp::Records::Detail.new(account, 'quotes').build('somosemp', '4119') }

    it 'builds the header, items, the quote -> OS -> pedido chain and the timeline' do
      expect(detail['header']).to include('status' => 'NEGOCIAÇÃO', 'contato' => 'Gilmar')
      expect(detail['itens']).to eq([{ 'codigo' => 491, 'descricao' => 'MOLA', 'servico' => false, 'unidade' => '', 'quantidade' => 2.0,
                                       'unitario' => 142.0, 'desconto' => 0.0, 'total' => 284.0 }])
      expect(detail['chain'].map { |node| [node['kind'], node['numero'], node['status'], node['current']] })
        .to eq([['quotes', 4119, 'NEGOCIAÇÃO', true], ['orders', 310, 'FECHADA', false], ['sales', 155, 'FATURADO', false]])
      expect(detail['timeline'].pluck('type').first(3)).to eq(%w[created created delivered])
      expect(detail['timeline'].pluck('type').last(2)).to contain_exactly('created', 'invoiced')
      expect(detail['edit']).to eq('allowed' => true, 'in_use_by' => nil)
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
