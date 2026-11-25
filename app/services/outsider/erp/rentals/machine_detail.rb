# OUTSIDER: a ficha de uma máquina (equipamentos) para o painel da aba Máquinas: dados técnicos, situação de agora (EM OS,
# LOCADA...), dono e onde está, e tudo o que se liga a ela em todas as unidades que enxergam o mesmo cadastro
# (Outsider::Erp::Rentals::Fleet): os contratos em que ela entrou (detalhecontrato), as OS (os.CodigoMaquina), os pedidos
# dessas OS (pedido.OS), as notas desses pedidos (notafiscal.Pedido, notafiscalservico.Pedido) e as faturas de locação
# (detalhefaturacontrato). A linha do tempo junta tudo; a tela filtra por OS, contratos e notas. Só leitura.
class Outsider::Erp::Rentals::MachineDetail < Outsider::Erp::Rentals::Reader
  HEADER = {
    'numero' => %w[Seq], 'codigo' => %w[Codigo], 'descricao' => %w[Descricao], 'modelo' => %w[Modelo], 'serie' => %w[NSerie],
    'patrimonio' => %w[NPatrimonio], 'ano' => %w[AnoFabricacao Ano], 'capacidade' => %w[CapacidadeCarga], 'elevacao' => %w[ElevacaoUtil],
    'altura_mastro' => %w[AlturaMastro], 'mastro' => %w[Mastro], 'mastro_elevado' => %w[MastroElevado], 'rodas' => %w[Rodas],
    'voltagem' => %w[Voltagem], 'acessorios' => %w[Acessorios], 'descricao_tecnica' => %w[DescrTec], 'inicio_operacao' => %w[InicioOperacao],
    'garantia' => %w[GarantiaAte], 'valor_locacao' => %w[VrLocacao], 'nf_aquisicao' => %w[NFAquisicao], 'cadastro' => %w[Cadastro],
    'dono_codigo' => %w[CodClientes]
  }.freeze
  ORDER = { 'numero' => %w[CodigoOS], 'data' => %w[DataEntrada], 'status' => %w[Situacao], 'atendimento' => %w[TipoAtendimento],
            'total' => %w[Total], 'entrega' => %w[DataEntrega], 'horimetro' => %w[Horimetro], 'tecnico' => %w[Tecnico],
            'cliente_codigo' => %w[CodigoCliente] }.freeze
  SALE = { 'numero' => %w[CodigoPedido], 'data' => %w[PedidoData], 'total' => %w[total Total], 'os' => %w[OS] }.freeze
  NOTE = { 'numero' => %w[CodigoNF], 'data' => %w[Emissao], 'status' => %w[Status], 'total' => %w[TotalNF total], 'pedido' => %w[Pedido] }.freeze
  SERVICE_NOTE = { 'numero' => %w[SeqNFSe], 'data' => %w[Emissao], 'status' => %w[Status], 'total' => %w[TotalNF Total],
                   'pedido' => %w[Pedido], 'nfse' => %w[CodigoNFS] }.freeze
  LIMIT = 100

  def build(company, number)
    check!(company)
    base = @fleet.base(company)
    header = header(base, number)
    members = @fleet.members(base)
    links = links(members, number)
    {
      'kind' => 'machines', 'company' => base, 'numero' => number.to_i, 'header' => header,
      'dono' => header['propria'].to_i == 1 ? {} : customer(base, header['dono_codigo']),
      'agora' => now(header, links[:contracts]), 'timeline' => timeline(links)
    }.merge(links.transform_keys(&:to_s)).merge(contact(base, header['propria'].to_i == 1 ? 0 : header['dono_codigo']))
  end

  private

  def header(base, number)
    sql = "SELECT #{list(base, 'equipamentos', 'O', HEADER)}, #{@machine_status.status} AS situacao, #{@machine_status.fields.join(', ')} " \
          "FROM #{S.ident(base)}.equipamentos O#{status_joins(base)} WHERE O.`Seq` = #{S.int(number)}"
    run(sql).first || raise(NotFound, number.to_s)
  end

  def links(members, number)
    contracts = contracts(members, number)
    orders = orders(members, number)
    sales = sales(orders)
    { contracts: contracts, orders: orders, sales: sales, invoices: notes(sales, 'notafiscal', NOTE),
      service_invoices: notes(sales, 'notafiscalservico', SERVICE_NOTE), rental_invoices: rental_invoices(members, number) }
  end

  # onde a máquina está agora: o contrato ativo (com o cliente dele) e a OS aberta
  def now(header, contracts)
    active = contracts.find { |row| row['contrato'].to_i == header['contrato'].to_i && row['banco'] == header['contrato_banco'] }
    place = active ? active.slice('banco', 'contrato', 'tipo', 'saida', 'retorno_previsto', 'valor', 'cliente_codigo', 'cliente') : {}
    { 'situacao' => header['situacao'], 'contrato' => place.presence,
      'os' => header['os_aberta'].to_i.positive? ? { 'banco' => header['os_banco'], 'numero' => header['os_aberta'].to_i } : nil }.compact
  end

  def contracts(members, number)
    sql = union(members, order: 'X.saida DESC, X.contrato DESC', limit: LIMIT) do |member|
      next unless column?(member, 'detalhecontrato', 'CodigoEquipto')

      bank = S.ident(member)
      "SELECT #{S.str(member)} AS banco, #{list(member, 'detalhecontrato', 'D', ITEM)}, #{list(member, 'contrato', 'C', CONTRACT)}, " \
        "#{client_name(member)} AS cliente FROM #{bank}.detalhecontrato D JOIN #{bank}.contrato C ON C.`CodigoContrato` = D.`CodigoContrato` " \
        "LEFT JOIN #{bank}.clientes K ON K.`CodigoCliente` = C.`CodigoCliente` WHERE D.`CodigoEquipto` = #{S.int(number)}"
    end
    run(sql).map { |row| row.merge('devolvida' => past?(row['retorno'])) }
  end

  def client_name(company)
    column = @schema.pick(company, 'clientes', Outsider::Erp::Records::Query::CLIENT[:cliente])
    column ? "K.#{S.column(column)}" : 'NULL'
  end

  def orders(members, number)
    sql = union(members, order: 'X.data DESC, X.numero DESC', limit: LIMIT) do |member|
      "SELECT #{S.str(member)} AS banco, #{list(member, 'os', 'O', ORDER)}, #{client_name(member)} AS cliente " \
        "FROM #{S.ident(member)}.os O LEFT JOIN #{S.ident(member)}.clientes K ON K.`CodigoCliente` = O.`CodigoCliente` " \
        "WHERE O.`CodigoMaquina` = #{S.int(number)}"
    end
    run(sql).map { |row| row.merge('tecnico_nome' => technician(row)) }
  end

  def technician(row)
    @technicians ||= {}
    key = [row['banco'], row['tecnico'].to_i]
    @technicians[key] ||= person(*key).to_s if key.last.positive?
  end

  # pedidos das OS da máquina (pedido.OS), por unidade
  def sales(orders)
    sql = union(orders.group_by { |row| row['banco'] }.keys, order: 'X.data DESC', limit: LIMIT) do |member|
      numbers = orders.select { |row| row['banco'] == member }.map { |row| row['numero'].to_i }
      "SELECT #{S.str(member)} AS banco, #{list(member, 'pedido', 'O', SALE)} FROM #{S.ident(member)}.pedido O " \
        "WHERE O.`OS` IN (#{numbers.join(', ')})"
    end
    run(sql)
  end

  def notes(sales, table, mapping)
    sql = union(sales.group_by { |row| row['banco'] }.keys, order: 'X.data DESC', limit: LIMIT) do |member|
      numbers = sales.select { |row| row['banco'] == member }.map { |row| row['numero'].to_i }
      "SELECT #{S.str(member)} AS banco, #{list(member, table, 'O', mapping)} FROM #{S.ident(member)}.#{table} O " \
        "WHERE O.`Pedido` IN (#{numbers.join(', ')})"
    end
    run(sql)
  end

  def rental_invoices(members, number)
    sql = union(members, order: 'X.data DESC', limit: LIMIT) do |member|
      next unless column?(member, 'detalhefaturacontrato', 'CodigoEquipto')

      bank = S.ident(member)
      "SELECT DISTINCT #{S.str(member)} AS banco, #{list(member, 'faturacontrato', 'F', INVOICE)}, M.`CodigoContrato` AS contrato " \
        "FROM #{bank}.detalhefaturacontrato M JOIN #{bank}.faturacontrato F ON F.`CodigoFatura` = M.`CodigoFatura` AND F.`Serie` = M.`Serie` " \
        "WHERE M.`CodigoEquipto` = #{S.int(number)}"
    end
    run(sql)
  end

  def timeline(links)
    events = links[:contracts].flat_map { |row| contract_events(row) }
    events += links[:orders].flat_map { |row| order_events(row) }
    events += links[:invoices].map { |row| note_event(row, 'invoices') }
    events += links[:service_invoices].map { |row| note_event(row, 'service_invoices') }
    events += links[:rental_invoices].map { |row| rental_event(row) }
    chronological(events)
  end

  def contract_events(row)
    ref = { 'group' => 'contracts', 'kind' => 'contracts', 'company' => row['banco'], 'numero' => row['contrato'], 'tipo' => row['tipo'],
            'cliente' => row['cliente'] }
    list = [event(row['saida'], 'machine_out', ref)]
    list << event(row['retorno'], 'machine_back', ref) if row['devolvida']
    list
  end

  def order_events(row)
    ref = { 'group' => 'orders', 'kind' => 'orders', 'company' => row['banco'], 'numero' => row['numero'], 'status' => row['status'],
            'atendimento' => row['atendimento'], 'horimetro' => row['horimetro'], 'name' => row['tecnico_nome'].presence,
            'cliente' => row['cliente'] }
    list = [event(row['data'], 'order', ref)]
    list << event(row['entrega'], 'order_delivered', ref) if row['entrega'].present?
    list
  end

  def note_event(row, kind)
    label = row['nfse'].to_i.positive? ? row['nfse'].to_i.to_s : nil
    event(row['data'], 'note', { 'group' => 'notes', 'kind' => kind, 'company' => row['banco'], 'numero' => row['numero'],
                                 'rotulo' => label, 'total' => row['total'], 'pedido' => row['pedido'] })
  end

  def rental_event(row)
    event(row['data'], 'rental_invoice', { 'group' => 'notes', 'kind' => 'rental_invoices', 'company' => row['banco'], 'numero' => row['numero'],
                                           'total' => row['total'], 'contrato' => row['contrato'] })
  end
end
