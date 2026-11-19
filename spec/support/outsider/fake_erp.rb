# OUTSIDER: ERP Mais Prático simulado para os testes do orçamento de peças e serviços. Responde o PUT
# /dashboard/api/query_execute conforme a SQL recebida e guarda as linhas gravadas (a função de item descarta em silêncio
# o que estiver em drop, como o ERP faz com item sem NCM). Nenhuma chamada real sai nos testes.
class OutsiderFakeErp
  COLUMNS = {
    'clientes' => %w[CodigoCliente Nome Apelido CPF_CNPJ RGIE Endereco Numero Bairro Cidade UF cep TelResidencia Celular email],
    'produtos' => %w[CodigoProduto Descricao Unidade PrecoVenda Tipo ClasFiscal estoque Ativo CodigoFabrica DescrTec],
    'formapagto' => %w[Codigo Descricao],
    'orcamento' => %w[codigoorcamento CodigoCliente orcamentoData FormaPagto Vendedor Contato Telefone Observacoes Status PrazoEntrega
                      Validade PrazoGarantia ICMS IPI totalServicos total AutorizadoPor DataAutorizadoPor],
    'detalheorcamento' => %w[CodigoOrcamento CodigoItem CodigoProduto Quantidade PrecoUnitario Desconto TotalLinha ClasFiscal SitTrib],
    'empresa' => %w[NomeImpressao CNPJ TelefoneImpressao EmailImpressao],
    'funcionarios' => %w[CodigoFuncionario Nome Senha Vendedor Gerente gerenteComercial CargoGerente],
    'ac_desconto' => %w[Funcionario Inclusao Alteracao]
  }.freeze
  # quem libera desconto: código => [nome, gerente, permissão de desconto]; a senha de todos é "segredo" (MD5, como o ERP)
  APPROVERS = { 7 => ['CRISTIANE', 1, 0], 12 => ['CARLOS', 0, 1], 30 => ['JOAO', 0, 0] }.freeze
  PASSWORD_MD5 = Digest::MD5.hexdigest('segredo')
  PRODUCTS = { 491 => 0, 923 => 0, 503 => 1 }.freeze

  attr_reader :sqls, :lines
  attr_accessor :drop, :fail_on_item

  def initialize(number: 5001)
    @number = number
    @sqls = []
    @lines = []
    @drop = []
    @fail_on_item = nil
  end

  def answer(sql)
    @sqls << sql
    return schema(sql) if sql.include?('information_schema')

    writes(sql) || reads(sql) || []
  end

  def writes_made = @sqls.grep(/sp_Cadastra|INSERT INTO|UPDATE /)

  private

  def schema(sql)
    COLUMNS.fetch(sql[/LOWER\(TABLE_NAME\) = '(\w+)'/, 1], []).map { |name| { 'COLUMN_NAME' => name } }
  end

  def writes(sql)
    if sql.include?('sp_CadastraOrcamento') then [{ 'codigo' => @number }]
    elsif sql.include?('sp_CadastraItemOrcamento') then item(sql[/sp_CadastraItemOrcamento\(\d+, (\d+),/, 1].to_i)
    elsif sql.start_with?('INSERT INTO') then service(sql[/P\.CodigoProduto = (\d+) AND P\.Tipo = 1/, 1].to_i)
    elsif sql.include?('sp_FinalizaOrcamento') then [{ 'resultado' => 'OK' }]
    elsif sql.start_with?('UPDATE ') then []
    end
  end

  # fail_on_item: essa chamada cai uma vez (ERP fora do ar no meio da gravação)
  def item(code)
    if @fail_on_item == code
      @fail_on_item = nil
      raise Outsider::Erp::Client::Error, 'Net::ReadTimeout'
    end

    @lines << code unless @drop.include?(code)
    [{ 'codigo' => 1 }]
  end

  def service(code)
    @lines << code if PRODUCTS[code] == 1
    []
  end

  # marcador na SQL => resposta (a primeira que bater)
  def reads(sql)
    {
      'SELECT CodigoItem, CodigoProduto' => -> { @lines.map { |code| { 'CodigoProduto' => code } } },
      'CodigoProduto IN' => -> { kinds(sql) }, '.clientes C' => -> { [customer] }, '.orcamento O WHERE' => -> { [header] },
      '.detalheorcamento D' => -> { report_lines },
      '.empresa E' => -> { [{ 'nome__0' => 'SOMOS EMPILHADEIRAS LTDA', 'cnpj__0' => '52346349000183' }] },
      '.funcionarios L' => -> { approver(sql) },
      '.funcionarios F' => -> { [{ 'nome' => 'CRISTIANE', 'codigo' => 7 }] },
      '.formapagto F' => -> { [{ 'Codigo' => 3, 'Descricao' => '28/56/84 DIAS' }] }
    }.find { |marker, _| sql.include?(marker) }&.last&.call
  end

  def approver(sql)
    code = sql[/L\.`CodigoFuncionario` = (\d+)/, 1].to_i
    name, manager, permission = APPROVERS[code]
    return [] unless name && sql.include?("'#{PASSWORD_MD5}'")

    [{ 'nome' => name, 'gerente' => manager, 'ac_desconto' => permission }]
  end

  def kinds(sql)
    sql[/IN \(([\d, ]+)\)/, 1].split(', ').map(&:to_i).filter_map { |code| { 'codigo' => code, 'tipo' => PRODUCTS[code] } if PRODUCTS.key?(code) }
  end

  def customer
    { 'codigo' => 716, 'documento' => '12345678000190', 'uf' => 'GO', 'nome' => 'SUPERMERCADO ALVORADA GOIANO LTDA',
      'email' => 'compras@alvorada.com.br; nf@alvorada.com.br', 'cidade' => 'GOIÂNIA' }
  end

  def header
    { 'cliente' => 716, 'data' => '2026-11-19 10:00:00', 'pagamento' => '28/56/84 DIAS', 'vendedor' => 7, 'contato' => 'Gilmar Souza',
      'observacoes' => 'TIMAO MODELO CBD', 'status' => 'NEGOCIAÇÃO', 'prazo_entrega' => '5 dias úteis', 'validade' => '10 dias',
      'garantia' => '90 dias', 'total' => 3809.27 }
  end

  def report_lines
    [{ 'codigo' => 923, 'descricao' => 'TIMAO CBD-20J-LI3', 'unidade' => 'UN', 'quantidade' => 1, 'unitario' => 3181.47, 'desconto_un' => 0,
       'total' => 3181.47, 'ncm' => '84312011', 'cst' => '200', 'icms' => 19 },
     { 'codigo' => 491, 'descricao' => 'MOLA GAS', 'unidade' => 'UN', 'quantidade' => 1, 'unitario' => 142, 'desconto_un' => 14.2,
       'total' => 127.8, 'ncm' => '84312011', 'cst' => '200', 'icms' => 19 },
     { 'codigo' => 503, 'descricao' => 'HORA TECNICA AVULSO', 'unidade' => 'UN', 'quantidade' => 2, 'unitario' => 250, 'desconto_un' => 0,
       'total' => 500 }]
  end
end

module OutsiderFakeErpHelpers
  def stub_fake_erp(fake = OutsiderFakeErp.new)
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      { status: 200, body: fake.answer(JSON.parse(request.body)['SQL_Execute']).to_json }
    end
    fake
  end
end

RSpec.configure { |config| config.include OutsiderFakeErpHelpers }
