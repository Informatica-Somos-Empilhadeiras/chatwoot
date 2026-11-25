# OUTSIDER: o detalhe de um contrato do ERP (locação, manutenção ou prestação de serviço) para o painel da aba Contratos:
# cabeçalho (vigência, valor, faturamento, pagamento, entrega), cliente, as máquinas do contrato (detalhecontrato, com a
# saída, o retorno e a situação de agora de cada uma), as faturas de locação (faturacontratocorrelacao -> faturacontrato),
# as OS das máquinas desde o início do contrato e a linha do tempo do contrato. Só leitura, no banco da unidade.
class Outsider::Erp::Rentals::ContractDetail < Outsider::Erp::Rentals::Reader
  HEADER = {
    'numero' => %w[CodigoContrato], 'data' => %w[DataEmissao], 'status' => %w[Status], 'data_status' => %w[DataStatus],
    'tipo' => %w[TipoContratos], 'cliente_codigo' => %w[CodigoCliente], 'vendedor' => %w[CodigoVendedor], 'inicio' => %w[DataInicio],
    'termino' => %w[DataTermino], 'dias' => %w[DiasContrato], 'meses' => %w[MesesContrato], 'periodicidade' => %w[periodicidadeContrato],
    'total' => %w[Total], 'parcela' => %w[Vrparcelas], 'parcelas' => %w[Qtdparcelas], 'pagamento' => %w[FormaPagto],
    'dia_pagamento' => %w[DiaPagto], 'dia_faturamento' => %w[DiaFaturamento], 'contato' => %w[ContatoCliente],
    'observacoes' => %w[Observacoes], 'orcamento' => %w[orcamento], 'entrega_endereco' => %w[EnderecoEntrega],
    'entrega_numero' => %w[NumeroEntrega], 'entrega_bairro' => %w[BairroEntrega], 'entrega_cidade' => %w[CidadeEntrega],
    'entrega_uf' => %w[UFEntrega], 'obra' => %w[ObraEntr]
  }.freeze
  ORDER = { 'numero' => %w[CodigoOS], 'data' => %w[DataEntrada], 'status' => %w[Situacao], 'atendimento' => %w[TipoAtendimento],
            'maquina' => %w[CodigoMaquina], 'total' => %w[Total], 'entrega' => %w[DataEntrega] }.freeze
  LIMIT = 60

  def build(company, number)
    check!(company)
    header = header(company, number)
    header = header.merge('vendedor_nome' => person(company, header['vendedor']))
    machines = machines(company, number)
    invoices = invoices(company, number)
    orders = orders(company, header, machines)
    {
      'kind' => 'contracts', 'company' => company, 'numero' => number.to_i, 'header' => header,
      'cliente' => customer(company, header['cliente_codigo']), 'maquinas' => machines, 'faturas' => invoices, 'ordens' => orders,
      'proxima_fatura' => next_billing(header), 'timeline' => timeline(company, header, machines, invoices, orders)
    }.merge(contact(company, header['cliente_codigo']))
  end

  private

  def header(company, number)
    sql = "SELECT #{list(company, 'contrato', 'O', HEADER)} FROM #{S.ident(company)}.contrato O WHERE O.`CodigoContrato` = #{S.int(number)}"
    run(sql).first || raise(NotFound, number.to_s)
  end

  def machines(company, number)
    bank = S.ident(company)
    sql = "SELECT #{list(company, 'detalhecontrato', 'D', ITEM)}, #{machine_fields(company)} FROM #{bank}.detalhecontrato D " \
          "LEFT JOIN #{bank}.equipamentos O ON O.`Seq` = D.`CodigoEquipto`#{status_joins(company)} " \
          "WHERE D.`CodigoContrato` = #{S.int(number)} ORDER BY D.`CodigoItem` LIMIT #{LIMIT}"
    run(sql).map { |row| row.merge('devolvida' => returned?(row), 'base' => @fleet.base(company)) }
  end

  def invoices(company, number)
    bank = S.ident(company)
    count = "(SELECT COUNT(*) FROM #{bank}.detalhefaturacontrato M WHERE M.`CodigoFatura` = F.`CodigoFatura` AND M.`Serie` = F.`Serie` " \
            "AND M.`CodigoContrato` = #{S.int(number)}) AS maquinas"
    sql = "SELECT #{list(company, 'faturacontrato', 'F', INVOICE)}, #{count} FROM #{bank}.faturacontratocorrelacao R " \
          "JOIN #{bank}.faturacontrato F ON F.`CodigoFatura` = R.`CodigoFatura` AND F.`Serie` = R.`Serie` " \
          "WHERE R.`CodigoContrato` = #{S.int(number)} ORDER BY F.`DataEmissao` DESC, F.`CodigoFatura` DESC LIMIT #{LIMIT}"
    run(sql)
  end

  # as OS das máquinas do contrato abertas desde o início dele, em todas as unidades que enxergam o mesmo cadastro
  def orders(company, header, machines)
    seqs = machines.filter_map { |row| row['maquina'].to_i if row['maquina'].to_i.positive? }.uniq
    return [] if seqs.empty?

    since = header['inicio'].present? ? " AND O.`DataEntrada` >= #{S.date(header['inicio'])}" : ''
    sql = union(@fleet.members(@fleet.base(company)), order: 'X.data DESC, X.numero DESC', limit: LIMIT) do |member|
      "SELECT #{S.str(member)} AS banco, #{list(member, 'os', 'O', ORDER)} FROM #{S.ident(member)}.os O " \
        "WHERE O.`CodigoMaquina` IN (#{seqs.join(', ')})#{since}"
    end
    run(sql)
  end

  # o próximo dia de faturamento (DiaFaturamento) enquanto o contrato está ativo e na vigência
  def next_billing(header)
    day = header['dia_faturamento'].to_i
    return unless day.between?(1, 31) && header['status'].to_s.upcase == 'ATIVO'

    date = billing_day(day)
    ending = Time.zone.parse(header['termino'].to_s)&.to_date
    date.iso8601 if ending.nil? || date <= ending
  end

  # o dia de faturamento deste mês ou, se já passou, o do mês que vem (dia 31 vira o último dia do mês)
  def billing_day(day)
    today = Time.zone.today
    [today, today.next_month].map { |base| base.change(day: [day, base.end_of_month.day].min) }.find { |item| item >= today }
  end

  def timeline(company, header, machines, invoices, orders)
    base = { 'kind' => 'contracts', 'company' => company, 'numero' => header['numero'] }
    events = contract_events(header, base) + machines.flat_map { |row| machine_events(row, base) }
    events += invoices.map { |row| event(row['data'], 'rental_invoice', invoice_ref(company, row)) }
    events += orders.map { |row| event(row['data'], 'order', order_ref(row)) }
    chronological(events)
  end

  def contract_events(header, base)
    events = [event(header['data'], 'contract_created', base), event(header['inicio'], 'contract_start', base)]
    events << event(header['termino'], past?(header['termino']) ? 'contract_end' : 'contract_due', base)
    events << event(header['data_status'], 'contract_status', base.merge('status' => header['status'])) if closed?(header)
    events
  end

  def closed?(header) = header['status'].present? && header['status'].to_s.upcase != 'ATIVO'

  def machine_events(row, base)
    machine = row.slice('descricao', 'modelo', 'serie').merge('maquina' => row['maquina'], 'machine_company' => row['base'])
    list = [event(row['saida'], 'machine_out', base.merge(machine))]
    list << event(row['retorno'], 'machine_back', base.merge(machine)) if row['devolvida']
    list
  end

  def invoice_ref(company, row)
    { 'kind' => 'rental_invoices', 'company' => company, 'numero' => row['numero'], 'total' => row['total'], 'status' => row['status'] }
  end

  def order_ref(row)
    { 'kind' => 'orders', 'company' => row['banco'], 'numero' => row['numero'], 'status' => row['status'],
      'atendimento' => row['atendimento'], 'maquina' => row['maquina'] }
  end
end
