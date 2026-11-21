# OUTSIDER: os pedidos de uma unidade para o relatório dos técnicos (Outsider::Erp::TechnicianReport): os faturados no
# período (notas válidas emitidas entre as datas, somadas por pedido) com o vínculo técnico/OS do chat, e os que têm
# técnico informado mas ainda nenhuma nota válida (aguardando faturamento).
class Outsider::Erp::TechnicianReport::Unit
  def initialize(account, lookup, company)
    @account = account
    @lookup = lookup
    @company = company
  end

  def sales(from, to)
    notes = @lookup.notes_between(@company, from, to).group_by { |note| note['pedido'].to_i }
    return [] if notes.empty?

    links = attributions.where(order_number: notes.keys).index_by(&:order_number)
    context = context(notes.keys, links.values)
    notes.map { |number, list| sale_row(number, list, links[number], context) }
  end

  # técnico informado, mas o pedido ainda sem nenhuma nota válida (de qualquer data)
  def pending(since)
    links = attributions.where(updated_at: since..).index_by(&:order_number)
    return [] if links.empty?

    billed = @lookup.notes_for(@company, links.keys).keys
    waiting = links.except(*billed)
    context = context(waiting.keys, waiting.values)
    waiting.map { |number, link| sale_row(number, [], link, context).except('notas', 'data_nota') }
  end

  private

  def attributions
    Outsider::Erp::SaleAttribution.where(account_id: @account.id, company: @company).where('jsonb_array_length(lines) > 0')
  end

  def context(numbers, links)
    sales = @lookup.sales(@company, numbers)
    orders = @lookup.orders(@company, links.flat_map(&:os_numbers))
    codes = sales.values.pluck('vendedor') + links.flat_map { |link| link.lines.pluck('tecnico_codigo') }
    { sales: sales, orders: orders, people: @lookup.people(@company, codes), clients: @lookup.clients(@company, sales.values.pluck('cliente')) }
  end

  def sale_row(number, notes, link, context)
    sale = context[:sales][number] || {}
    {
      'unidade' => @company, 'pedido' => number, 'data_pedido' => sale['data'], 'data_nota' => notes.pluck('data').compact.min,
      'notas' => notes.map { |note| note_label(note) }, 'vendedor' => context[:people][sale['vendedor'].to_i],
      'cliente_codigo' => sale['cliente'].to_i, 'cliente' => context[:clients][sale['cliente'].to_i], 'linhas' => lines(link, context)
    }.merge(values(notes, sale))
  end

  # faturado: NF-e = peças, NFS-e = serviços; sem nota (aguardando), o total do pedido
  def values(notes, sale)
    parts = notes.select { |note| note['kind'] == 'invoices' }.sum { |note| note['total'].to_f }
    services = notes.select { |note| note['kind'] == 'service_invoices' }.sum { |note| note['total'].to_f }
    { 'pecas' => parts.round(2), 'servicos' => services.round(2), 'total' => (notes.any? ? parts + services : sale['total'].to_f).round(2) }
  end

  def note_label(note)
    { 'tipo' => note['kind'] == 'invoices' ? 'NF-e' : 'NFS-e', 'numero' => (note['rotulo'].to_i.nonzero? || note['numero']).to_i,
      'total' => note['total'].to_f.round(2) }
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
