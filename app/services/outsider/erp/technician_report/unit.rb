# OUTSIDER: os pedidos de uma unidade para o relatório dos técnicos (Outsider::Erp::TechnicianReport): os faturados no
# período (notas válidas emitidas entre as datas, somadas por pedido) com o técnico, e os que têm técnico informado mas
# ainda nenhuma nota válida (aguardando faturamento). O técnico vem do vínculo informado no chat; sem ele, das OS que o
# próprio ERP liga ao pedido (pedido.OS e as OS do mesmo orçamento), com o valor dividido pelo total de cada OS.
class Outsider::Erp::TechnicianReport::Unit
  # o vínculo que vem do ERP, no mesmo formato do informado no chat (Outsider::Erp::SaleAttribution)
  ErpLink = Struct.new(:lines) do
    def os_numbers = lines.map { |line| line['os'].to_i }
  end

  def initialize(account, lookup, company)
    @account = account
    @lookup = lookup
    @company = company
  end

  def sales(from, to)
    notes = @lookup.notes_between(@company, from, to).group_by { |note| note['pedido'].to_i }
    return [] if notes.empty?

    sales = @lookup.sales(@company, notes.keys)
    links = attributions.where(order_number: notes.keys).index_by(&:order_number)
    links = erp_links(sales.except(*links.keys)).merge(links)
    context = context(sales, links.values)
    notes.map { |number, list| sale_row(number, list, links[number], context) }
  end

  # técnico informado, mas o pedido ainda sem nenhuma nota válida (de qualquer data)
  def pending(since)
    links = attributions.where(updated_at: since..).index_by(&:order_number)
    return [] if links.empty?

    billed = @lookup.notes_for(@company, links.keys).keys
    waiting = links.except(*billed)
    context = context(@lookup.sales(@company, waiting.keys), waiting.values)
    waiting.map { |number, link| sale_row(number, [], link, context).except('notas', 'data_nota') }
  end

  private

  def attributions
    Outsider::Erp::SaleAttribution.where(account_id: @account.id, company: @company).where('jsonb_array_length(lines) > 0')
  end

  # { pedido => ErpLink } das OS com técnico que o ERP liga a cada pedido sem vínculo do chat
  def erp_links(sales)
    return {} if sales.empty?

    orders = @lookup.orders_for_sales(@company, sales.values).select { |order| order['tecnico'].to_i.positive? }
    sales.filter_map do |number, sale|
      linked = orders.select { |order| order['numero'].to_i == sale['os'].to_i || linked_quote?(order, sale) }
      [number, ErpLink.new(erp_lines(linked))] if linked.any?
    end.to_h
  end

  def linked_quote?(order, sale) = sale['orcamento'].to_i.positive? && order['orcamento'].to_i == sale['orcamento'].to_i

  # parte de cada OS pelo total dela (todas sem total: partes iguais)
  def erp_lines(orders)
    totals = orders.map { |order| [order['total'].to_f, 0].max }
    sum = totals.sum
    orders.zip(totals).map do |order, total|
      part = sum.positive? ? total * 100 / sum : 100.0 / orders.size
      { 'os' => order['numero'].to_i, 'parte' => part, 'tecnico_codigo' => order['tecnico'].to_i }
    end
  end

  def context(sales, links)
    orders = @lookup.orders(@company, links.flat_map(&:os_numbers))
    codes = sales.values.pluck('vendedor') + links.flat_map { |link| link.lines.pluck('tecnico_codigo') }
    { sales: sales, orders: orders, people: @lookup.people(@company, codes), clients: @lookup.clients(@company, sales.values.pluck('cliente')) }
  end

  def sale_row(number, notes, link, context)
    sale = context[:sales][number] || {}
    {
      'unidade' => @company, 'pedido' => number, 'data_pedido' => sale['data'], 'data_nota' => notes.pluck('data').compact.min,
      'notas' => notes.map { |note| note_label(note) }, 'vendedor' => context[:people][sale['vendedor'].to_i],
      'cliente_codigo' => sale['cliente'].to_i, 'cliente' => context[:clients][sale['cliente'].to_i], 'linhas' => lines(link, context),
      'origem' => origin(link)
    }.merge(values(notes, sale))
  end

  # faturado: NF-e = peças, NFS-e = serviços; sem nota (aguardando), o total do pedido
  def values(notes, sale)
    parts = notes.select { |note| note['kind'] == 'invoices' }.sum { |note| note['total'].to_f }
    services = notes.select { |note| note['kind'] == 'service_invoices' }.sum { |note| note['total'].to_f }
    { 'pecas' => parts.round(2), 'servicos' => services.round(2), 'total' => (notes.any? ? parts + services : sale['total'].to_f).round(2) }
  end

  def origin(link)
    return unless link

    link.is_a?(ErpLink) ? 'erp' : 'chat'
  end

  def note_label(note)
    { 'tipo' => note['kind'] == 'invoices' ? 'NF-e' : 'NFS-e', 'numero' => (note['rotulo'].to_i.nonzero? || note['numero']).to_i,
      'total' => note['total'].to_f.round(2), 'kind' => note['kind'], 'codigo' => note['numero'].to_i }
  end

  def lines(link, context)
    return [] unless link

    link.lines.map do |line|
      order = context[:orders][line['os'].to_i] || {}
      { 'os' => line['os'].to_i, 'parte' => line['parte'].to_f, 'tecnico_codigo' => line['tecnico_codigo'].to_i,
        'tecnico' => context[:people][line['tecnico_codigo'].to_i].presence || line['tecnico'],
        'data_os' => order['data'], 'atendimento' => order['atendimento'].to_s.strip.presence }
    end
  end
end
