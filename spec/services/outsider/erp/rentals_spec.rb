require 'rails_helper'

# OUTSIDER: Locação e máquinas (Outsider::Erp::Rentals e as listas contracts/machines/rental_invoices). O query_execute é
# simulado conforme a SQL recebida; aqui se confere a SQL (só SELECT, só os bancos das Configurações, máquina sem repetir
# entre as unidades que enxergam o mesmo cadastro) e o que a tela recebe (situação, vínculos e linha do tempo).
RSpec.describe 'Outsider ERP rentals and machines' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:detail_answers) do
    {
      'FROM somosemp.contrato O WHERE O.`CodigoContrato` = 1038' => [contract],
      "SELECT 'somosemp' AS banco, O.`CodigoContrato`" => [contract.merge('banco' => 'somosemp')],
      'FROM somosemp.detalhecontrato D LEFT JOIN' => [
        { 'item' => 1, 'contrato' => 1038, 'maquina' => 18_110, 'saida' => '2026-11-01T03:00:00.000Z', 'descricao' => 'EMPILHADEIRA 2,5T',
          'situacao' => 'LOCADA' },
        { 'item' => 2, 'contrato' => 1038, 'maquina' => 77_201, 'saida' => '2026-09-01T03:00:00.000Z', 'retorno' => '2026-10-16T03:00:00.000Z',
          'situacao' => 'EM OS' }
      ],
      'FROM somosemp.faturacontratocorrelacao R' => [{ 'numero' => 213, 'serie' => '1', 'data' => '2026-11-05T03:00:00.000Z', 'status' => 'IMPRESSA',
                                                       'total' => 14_700, 'maquinas' => 2 }],
      "SELECT 'somosemp' AS banco, O.`CodigoOS`" => [{ 'banco' => 'somosemp', 'numero' => 2080, 'data' => '2026-11-20T03:00:00.000Z',
                                                       'status' => 'ABERTA', 'tecnico' => 0 }],
      'FROM somosemp.equipamentos O' => [{ 'numero' => 18_110, 'descricao' => 'EMPILHADEIRA 2,5T', 'situacao' => 'LOCADA', 'propria' => 1,
                                           'contrato' => 1038, 'contrato_banco' => 'somosemp', 'dono_codigo' => 2 }],
      "SELECT 'somosemp' AS banco, D.`CodigoItem`" => [{ 'banco' => 'somosemp', 'contrato' => 1038, 'tipo' => 'CONTRATO DE LOCAÇÃO',
                                                         'saida' => '2026-11-01T03:00:00.000Z', 'cliente' => 'DISTRIBUIDORA' }],
      "SELECT 'somosemp' AS banco, O.`CodigoPedido`" => [{ 'banco' => 'somosemp', 'numero' => 1690, 'os' => 2080,
                                                           'data' => '2026-11-21T03:00:00.000Z' }],
      "SELECT 'somosemp' AS banco, O.`CodigoNF`" => [{ 'banco' => 'somosemp', 'numero' => 15_011, 'pedido' => 1690,
                                                       'data' => '2026-11-22T03:00:00.000Z' }]
    }
  end
  let(:user) { create(:user, account: account) }
  let(:columns) do
    {
      'contrato' => %w[CodigoContrato CodigoCliente CodigoVendedor TipoContratos Status DataEmissao DataInicio DataTermino
                       periodicidadeContrato Total Vrparcelas DiaFaturamento EnderecoEntrega DataStatus],
      'detalhecontrato' => %w[CodigoContrato CodigoItem CodigoEquipto PrecoUnitario TotalLinha DataLocacao DataRetorno PrevDataRetorno],
      'faturacontrato' => %w[CodigoFatura Serie DataEmissao Status TotalFatura CodigoDestinatario Vendedor NomeVendedor],
      'faturacontratocorrelacao' => %w[CodigoFatura Serie CodigoContrato],
      'detalhefaturacontrato' => %w[CodigoFatura Serie CodigoContrato CodigoItemContrato CodigoEquipto],
      'equipamentos' => %w[Seq Descricao Modelo NSerie NPatrimonio CodClientes Propriedade Proprietario Cadastro VrLocacao CapacidadeCarga],
      'os' => %w[CodigoOS CodigoCliente CodigoMaquina DataEntrada Situacao Total Tecnico DataEntrega Horimetro TipoAtendimento],
      'pedido' => %w[CodigoPedido PedidoData total OS],
      'notafiscal' => %w[CodigoNF Emissao Status TotalNF Pedido],
      'notafiscalservico' => %w[SeqNFSe Emissao Status TotalNF Pedido CodigoNFS],
      'clientes' => %w[CodigoCliente Nome Cidade UF],
      'funcionarios' => %w[CodigoFuncionario Nome Senha]
    }
  end
  let(:sqls) { [] }
  let(:contract) do
    { 'numero' => 1038, 'data' => '2026-10-28T03:00:00.000Z', 'status' => 'ATIVO', 'tipo' => 'CONTRATO DE LOCAÇÃO', 'cliente_codigo' => 709,
      'vendedor' => 0, 'inicio' => '2026-11-01T03:00:00.000Z', 'termino' => '2027-10-31T03:00:00.000Z', 'total' => 176_400,
      'parcela' => 14_700, 'dia_faturamento' => 5 }
  end

  before do
    account.update!(internal_attributes: { 'outsider_erp' => { 'enabled' => true, 'companies' => %w[somosemp somosfilial] } })
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      sql = JSON.parse(request.body)['SQL_Execute']
      sqls << sql
      { status: 200, body: answer(sql).to_json }
    end
  end

  def answer(sql)
    return schema_answer(sql) if sql.include?('information_schema')
    return [] if sql.include?('COUNT(*) AS qtd') || sql.include?(' AS dim, ')
    return [] if sql.start_with?('SELECT X.*')

    detail_answer(sql)
  end

  # equipamentos: tabela na matriz e VIEW do cadastro da matriz na filial
  def schema_answer(sql)
    return columns.fetch(sql[/LOWER\(TABLE_NAME\) = '(\w+)'/, 1], []).map { |name| { 'COLUMN_NAME' => name } } if sql.include?('COLUMNS')
    return [{ 'banco' => 'somosemp', 'tipo' => 'BASE TABLE' }, { 'banco' => 'somosfilial', 'tipo' => 'VIEW' }] if sql.include?('.TABLES')

    [{ 'banco' => 'somosfilial', 'definicao' => 'select `somosemp`.`equipamentos`.`Seq` AS `Seq` from `somosemp`.`equipamentos`' }]
  end

  def detail_answer(sql) = detail_answers.find { |fragment, _| sql.include?(fragment) }&.last || []

  def erp_sqls = sqls.grep_v(/information_schema/)
  def page_sql = erp_sqls.find { |sql| sql.start_with?('SELECT X.*') }

  describe 'lists' do
    it 'lists machines once (only banks with their own register) with the status from open OS and active contracts of every unit' do
      Outsider::Erp::Records::Lister.new(account, 'machines', user: user).page({ view: 'rented', q: '18110' })

      expect(page_sql).to include('FROM somosemp.equipamentos O', 'FROM somosemp.os S', 'FROM somosfilial.os S', 'FROM somosfilial.detalhecontrato D',
                                  "WHEN LEFT(MC.contrato_ref, 1) = '1' THEN 'LOCADA'", "X.status IN ('LOCADA')",
                                  "X.serie LIKE '%18110%'", 'IFNULL(MC.cliente, O.`CodClientes`)')
      expect(page_sql).not_to include('FROM somosfilial.equipamentos', 'Senha')
      expect(erp_sqls).to all(start_with('SELECT '))
    end

    it 'counts the own fleet in its view and filters contracts by type' do
      Outsider::Erp::Records::Lister.new(account, 'machines', user: user).page({ view: 'own' })
      expect(page_sql).to include('(X.propria = 1)')

      sqls.clear
      Outsider::Erp::Records::Lister.new(account, 'contracts', user: user).page({ view: 'expiring', tipo: "CONTRATO DE LOCAÇÃO'" })
      expect(page_sql).to include('FROM somosemp.contrato O', 'FROM somosfilial.contrato O', 'DATE_ADD(CURDATE(), INTERVAL 30 DAY)',
                                  "NULLIF(TRIM(X.tipo), '') = 'CONTRATO DE LOCAÇÃO\\''", 'AS maquinas')
    end
  end

  describe 'contract detail' do
    let(:detail) { Outsider::Erp::Rentals::ContractDetail.new(account).build('somosemp', 1038) }

    it 'brings the machines with their status, the rental invoices and the OS of those machines since the start' do
      travel_to(Time.zone.parse('2026-11-25 12:00')) do
        expect(detail['maquinas'].map { |row| [row['maquina'], row['situacao'], row['devolvida']] })
          .to eq([[18_110, 'LOCADA', false], [77_201, 'EM OS', true]])
        expect(detail['faturas'].first).to include('numero' => 213, 'maquinas' => 2)
        expect(detail['proxima_fatura']).to eq('2026-12-05')
        orders = erp_sqls.find { |sql| sql.include?('O.`CodigoMaquina` IN') }
        expect(orders).to include('O.`CodigoMaquina` IN (18110, 77201)', "O.`DataEntrada` >= '2026-11-01'", 'FROM somosfilial.os O')
      end
    end

    it 'puts the contract, the machines going out and back, invoices and OS on its own timeline' do
      travel_to(Time.zone.parse('2026-11-25 12:00')) do
        expect(detail['timeline'].pluck('type'))
          .to eq(%w[machine_out machine_back contract_created contract_start machine_out rental_invoice order contract_due])
        expect(detail['timeline'].find { |event| event['type'] == 'order' }).to include('kind' => 'orders', 'company' => 'somosemp', 'numero' => 2080)
      end
    end

    it 'refuses a bank outside the settings' do
      expect { Outsider::Erp::Rentals::ContractDetail.new(account).build('outrocliente', 1) }.to raise_error(ArgumentError)
      expect { Outsider::Erp::Rentals::ContractDetail.new(account).build('somosemp', 1) }.to raise_error(Outsider::Erp::Records::Detail::NotFound)
    end
  end

  describe 'machine detail' do
    it 'links contracts, OS, the OS sales orders and their invoices across the units that share the register' do
      detail = Outsider::Erp::Rentals::MachineDetail.new(account).build('somosfilial', 18_110)

      expect(detail['company']).to eq('somosemp')
      expect(detail['agora']).to include('situacao' => 'LOCADA', 'contrato' => include('contrato' => 1038, 'cliente' => 'DISTRIBUIDORA'))
      expect(erp_sqls.find { |sql| sql.include?('O.`CodigoMaquina` = 18110') }).to include('FROM somosemp.os O', 'FROM somosfilial.os O')
      expect(erp_sqls.find { |sql| sql.include?('.pedido O') }).to include('O.`OS` IN (2080)')
      expect(erp_sqls.find { |sql| sql.include?('.notafiscal O') }).to include('O.`Pedido` IN (1690)')
      expect(detail['timeline'].map { |event| [event['type'], event['group']] })
        .to eq([%w[machine_out contracts], %w[order orders], %w[note notes]])
      expect(erp_sqls).to all(start_with('SELECT '))
    end
  end

  describe 'same-day return' do
    it 'keeps a machine at the client when the ERP wrote the return date equal to the departure' do
      reader = Outsider::Erp::Rentals::ContractDetail.new(account)
      travel_to(Time.zone.parse('2026-11-25 12:00')) do
        expect(reader.send(:returned?, { 'saida' => '2026-11-01T03:00:00.000Z', 'retorno' => '2026-11-01T03:00:00.000Z' })).to be(false)
        expect(reader.send(:returned?, { 'saida' => '2026-11-01T03:00:00.000Z', 'retorno' => '2026-11-10T03:00:00.000Z' })).to be(true)
        expect(reader.send(:returned?, { 'saida' => '2026-11-01T03:00:00.000Z', 'retorno' => '2026-12-10T03:00:00.000Z' })).to be(false)
      end
      Outsider::Erp::Records::Lister.new(account, 'machines', user: user).page({ view: 'rented' })
      expect(page_sql).to include('DATE(D.`DataRetorno`) <= DATE(D.`DataLocacao`)')
    end
  end

  describe 'contacts of the ERP client' do
    it 'lists every chat contact linked to the client, the one with the latest conversation first' do
      buyer = create(:contact, account: account, name: 'Comprador')
      finance = create(:contact, account: account, name: 'Financeiro')
      settings = Outsider::Erp::Settings.new(account)
      [buyer, finance].each do |item|
        Outsider::Erp::ContactLink.new(item).add(company: 'somosemp', code: 709, name: 'DISTRIBUIDORA', settings: settings)
      end
      create(:conversation, account: account, contact: finance)

      detail = Outsider::Erp::Rentals::ContractDetail.new(account).build('somosemp', 1038)
      expect(detail['contacts'].pluck('name')).to eq(%w[Financeiro Comprador])
      expect(detail['contact_id']).to eq(finance.id)
    end
  end

  describe 'documents' do
    it 'prints the contract in the ready rental template and the machine sheet' do
      travel_to(Time.zone.parse('2026-11-25 12:00')) do
        contract_pdf = Outsider::Erp::Prints::Document.contract(account, 'somosemp', 1038)
        expect(contract_pdf.filename).to eq('Contrato 1038.pdf')
        expect(contract_pdf.render).to start_with('%PDF')
        expect(Outsider::Erp::PrintTemplate.where(account: account, kind: 'contract').pluck(:builtin))
          .to contain_exactly('contract_locacao', 'contract_manutencao')

        machine_pdf = Outsider::Erp::Prints::Document.machine(account, 'somosfilial', 18_110)
        expect(machine_pdf.render).to start_with('%PDF')
      end
    end

    it 'fills the contract values for the template' do
      values = Outsider::Erp::Prints::Values.new('contract', Outsider::Erp::Prints::Sample.contract, unit_name: 'Matriz').build
      expect(values['groups']['contrato']).to include('valor' => 'R$ 14.700,00 por mês', 'prazo' => '12 meses', 'faturamento' => 'Todo dia 5',
                                                      'tipo' => 'Locação')
      expect(values['tables']['maquinas'].first).to include('serie' => '18110', 'valor' => '9.800,00')
      expect(values['placeholders']).to include('cliente' => 'LOGÍSTICA ATLÂNTICO LTDA', 'documento' => '12.345.678/0001-90')
    end

    it 'uses the template chosen for the contract type' do
      Outsider::Erp::Prints::Defaults.ensure!(account, 'contract')
      chosen = Outsider::Erp::PrintTemplate.create!(account: account, kind: 'contract', name: 'Nosso contrato',
                                                    content: Outsider::Erp::Prints::Defaults.content('contract_locacao'))
      Outsider::Erp::Prints::Bindings.new(account).update('contract', default: 'original', types: { 'LOCAÇÃO' => chosen.id })

      expect(Outsider::Erp::Prints::Document.rental_template(account, 'contract', 'LOCACAO')).to eq(chosen)
      expect(Outsider::Erp::Prints::Document.rental_template(account, 'contract', 'MANUTENCAO').builtin).to eq('contract_manutencao')
    end
  end

  describe 'OS of a machine' do
    it 'filters the OS list by the machine in every unit that shares its register' do
      Outsider::Erp::Records::Lister.new(account, 'orders', user: user).page({ view: 'all', machine: 'somosemp:18110' })
      expect(page_sql).to include("(X.banco IN ('somosemp', 'somosfilial') AND X.maquina = 18110)", 'O.`CodigoMaquina` AS maquina')
    end
  end

  describe 'contact block' do
    it 'shows the contracts of the linked ERP clients with the machines still at the client' do
      result = Outsider::Erp::Rentals::ClientSummary.new(account).build([{ 'empresa' => 'somosemp', 'codigo' => 709 },
                                                                         { 'empresa' => 'x', 'codigo' => 1 }])

      expect(result['contracts'].first['maquinas'].pluck('maquina')).to eq([18_110])
      expect(erp_sqls.find { |sql| sql.include?('.contrato O') }).to include('O.`CodigoCliente` IN (709)')
      expect(erp_sqls.find { |sql| sql.include?('O.`CodClientes` IN (709)') }).to include('AND NOT (IFNULL(O.`Propriedade`, 1) = 0')
      expect(sqls.join).not_to include("'x'")
    end
  end
end
