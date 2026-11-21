# OUTSIDER: o vendedor informa no chat a OS (ou as OS) de um pedido de venda e o técnico vem dela. Como o Mais Prático
# não tem esses campos no pedido, isso fica só no Chatwoot (Outsider::Erp::SaleAttribution) e é a base do relatório de
# desempenho dos técnicos. A OS precisa existir na unidade e ter técnico; se o vendedor ou o cliente dela forem outros,
# ou se ela já estiver em outro pedido, só grava com a senha comercial (a mesma da liberação de desconto,
# Outsider::Erp::DiscountApprover). Com mais de uma OS, cada uma leva uma parte do valor (somam 100%). Regra da
# premiação: o vínculo manual é para a OS feita depois do faturamento, então ela precisa estar fechada/finalizada (aberta
# ou cancelada não grava). Pedido com OS já ligada no ERP não precisa de vínculo: o relatório usa a do ERP.
class Outsider::Erp::SaleAttributor
  class NotFound < StandardError; end

  class Invalid < StandardError
    attr_reader :details

    def initialize(reason, details = {})
      @details = details
      super(reason)
    end
  end

  MAX_LINES = 10
  # só OS feita e encerrada conta (a regra da premiação): aberta ainda não, cancelada/perdida nunca
  CLOSED_ORDER = /FECHAD|FINALIZ|ENCERR|CONCLU/i
  LOST_ORDER = Outsider::Erp::SaleLookup::LOST_ORDER
  # divergências que a senha comercial libera; as outras impedem de gravar
  APPROVABLE = %w[vendedor_diferente cliente_diferente ja_usada].freeze

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @settings = Outsider::Erp::Settings.new(@account)
    @lookup = Outsider::Erp::SaleLookup.new(@account)
  end

  # o pedido, o vínculo gravado e as OS sugeridas pelo próprio ERP (pedido.OS e as do mesmo orçamento)
  def show(company, number)
    sale = sale!(company, number)
    record = find(company, number)
    suggested = @lookup.linked_orders(company, sale).map { |row| row['numero'].to_i } - record.to_a.flat_map(&:os_numbers)
    { 'pedido' => describe_sale(company, sale), 'vinculo' => serialize(record), 'sugestoes' => check(company, sale, suggested) }
  end

  # confere as OS antes de gravar: técnico, vendedor, cliente e se já estão em outro pedido
  def preview(company, number, os_numbers)
    sale = sale!(company, number)
    { 'pedido' => describe_sale(company, sale), 'linhas' => check(company, sale, clean_numbers(os_numbers)) }
  end

  # lines: [{ os, parte }]; approval: { code, password } quando alguma OS não bate com o pedido
  def save(company, number, lines, approval = {})
    sale = sale!(company, number)
    shares = clean_lines(lines)
    checked = check(company, sale, shares.keys)
    blocking = checked.flat_map { |line| line['divergencias'] - APPROVABLE }
    raise Invalid.new(blocking.first, 'linhas' => checked) if blocking.any?

    approver = approve(company, checked, approval)
    store(company, number, checked.map { |line| stored_line(line, shares) }, approver, checked)
  end

  # tira o vínculo (o pedido volta a ficar sem técnico); o histórico continua
  def clear(company, number)
    record = find(company, number) || raise(NotFound)
    record.history += [history_entry('removed', [])]
    record.update!(lines: [], approval: {}, user: @account_user.user)
    serialize(record)
  end

  private

  def sale!(company, number)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company)

    @lookup.sales(company, [number]).values.first || raise(NotFound)
  end

  def find(company, number) = Outsider::Erp::SaleAttribution.find_by(account_id: @account.id, company: company, order_number: number.to_i)

  def clean_numbers(values) = Array(values).filter_map { |value| Integer(value.to_s, 10, exception: false) }.select(&:positive?).uniq

  # { os => parte } com as partes somando 100% (uma OS só leva 100%)
  def clean_lines(lines)
    list = parse_lines(lines)
    check_count!(list)
    return { list.first.first => 100.to_d } if list.one?
    raise Invalid, 'partes' unless valid_shares?(list.map(&:last))

    list.to_h.transform_values { |part| part.round(6) }
  end

  def check_count!(list)
    raise Invalid, 'sem_os' if list.empty?
    raise Invalid, 'muitas_os' if list.size > MAX_LINES
    raise Invalid, 'os_repetida' if list.map(&:first).uniq.size != list.size
  end

  def parse_lines(lines)
    Array(lines).map { |line| [Integer(line['os'].to_s, 10, exception: false).to_i, line['parte'].to_d] }.reject { |os, _| os <= 0 }
  end

  def valid_shares?(parts) = parts.all?(&:positive?) && (parts.sum - 100).abs <= 0.05

  # cada OS com o técnico, o vendedor e o cliente dela e o que não bate com o pedido
  def check(company, sale, numbers)
    return [] if numbers.empty?

    orders = @lookup.orders(company, numbers)
    used = used_elsewhere(company, sale['numero'].to_i, numbers)
    context = {
      sale: sale, used: used, people: @lookup.people(company, orders.values.flat_map { |row| [row['tecnico'], row['vendedor']] }),
      clients: @lookup.clients(company, orders.values.pluck('cliente'))
    }
    numbers.map { |number| orders[number] ? line(orders[number], context) : { 'os' => number, 'divergencias' => ['os_nao_encontrada'] } }
  end

  def line(order, context)
    number = order['numero'].to_i
    {
      'os' => number, 'situacao' => order['situacao'].to_s.strip, 'data' => order['data'], 'total' => order['total'].to_f.round(2),
      'atendimento' => order['atendimento'].to_s.strip.presence, 'pedido_usado' => context[:used][number],
      'divergencias' => divergences(order, context[:sale], context[:used][number])
    }.merge(order_people(order, context)).compact
  end

  def order_people(order, context)
    {
      'tecnico_codigo' => order['tecnico'].to_i, 'tecnico' => context[:people][order['tecnico'].to_i],
      'vendedor_codigo' => order['vendedor'].to_i, 'vendedor' => context[:people][order['vendedor'].to_i],
      'cliente_codigo' => order['cliente'].to_i, 'cliente' => context[:clients][order['cliente'].to_i]
    }
  end

  def divergences(order, sale, used_in)
    list = [('sem_tecnico' unless order['tecnico'].to_i.positive?), order_state(order['situacao'].to_s)]
    list << 'vendedor_diferente' if order['vendedor'].to_i.positive? && order['vendedor'].to_i != sale['vendedor'].to_i
    list << 'cliente_diferente' if order['cliente'].to_i != sale['cliente'].to_i
    list << 'ja_usada' if used_in
    list.compact
  end

  def order_state(status)
    return 'os_cancelada' if status.match?(LOST_ORDER)

    'os_aberta' unless status.match?(CLOSED_ORDER)
  end

  # { os => pedido } das OS que já estão no vínculo de outro pedido da mesma unidade
  def used_elsewhere(company, number, os_numbers)
    scope = Outsider::Erp::SaleAttribution.where(account_id: @account.id, company: company).where.not(order_number: number)
    scope = scope.where('lines @> ANY (ARRAY[?]::jsonb[])', os_numbers.map { |os| [{ os: os }].to_json })
    scope.each_with_object({}) { |record, map| (record.os_numbers & os_numbers).each { |os| map[os] = record.order_number } }
  end

  def approve(company, checked, approval)
    reasons = checked.flat_map { |line| line['divergencias'] }.uniq & APPROVABLE
    return if reasons.empty?

    approval = approval.to_h.with_indifferent_access
    raise Invalid.new('senha_comercial', 'linhas' => checked) if approval[:code].blank? || approval[:password].blank?

    person = Outsider::Erp::DiscountApprover.new(@account_user).verify(company, approval[:code], approval[:password])
    { 'by_code' => person[:code], 'by_name' => person[:name], 'at' => Time.current.iso8601, 'reasons' => reasons }
  end

  def stored_line(line, shares)
    { 'os' => line['os'], 'parte' => shares[line['os']].to_f, 'tecnico_codigo' => line['tecnico_codigo'], 'tecnico' => line['tecnico'] }
  end

  def store(company, number, lines, approver, checked)
    record = find(company, number) || Outsider::Erp::SaleAttribution.new(account: @account, company: company, order_number: number.to_i)
    record.history += [history_entry('saved', lines, approver)]
    record.assign_attributes(lines: lines, approval: approver || {}, user: @account_user.user)
    record.save!
    serialize(record).merge('linhas_conferidas' => checked)
  end

  def history_entry(action, lines, approver = nil)
    { 'at' => Time.current.iso8601, 'action' => action, 'user_id' => @account_user.user_id, 'name' => @account_user.user.name,
      'lines' => lines, 'approved_by' => approver&.dig('by_name') }.compact
  end

  def describe_sale(company, sale)
    people = @lookup.people(company, [sale['vendedor']])
    clients = @lookup.clients(company, [sale['cliente']])
    {
      'numero' => sale['numero'].to_i, 'data' => sale['data'], 'total' => sale['total'].to_f.round(2), 'vendedor_codigo' => sale['vendedor'].to_i,
      'vendedor' => people[sale['vendedor'].to_i], 'cliente_codigo' => sale['cliente'].to_i, 'cliente' => clients[sale['cliente'].to_i]
    }.compact
  end

  def serialize(record)
    return nil if record.nil? || record.lines.empty?

    { 'linhas' => record.lines, 'aprovado_por' => record.approval['by_name'], 'motivos' => record.approval['reasons'],
      'por' => record.user&.name, 'em' => record.updated_at.iso8601 }.compact
  end
end
