# OUTSIDER: as ligações do painel separadas por lugar e por dinheiro (Entrega 25): o mapa (estado do cliente
# pelo DDD, mais as internacionais), os custos do período (Outsider::Voice::CallCosts), as ligações por DDD
# e por filial (Telefonia > Configurações). Só ligações com cliente; entre ramais não entra.
class Outsider::Voice::CallBreakdown
  Region = Outsider::Voice::Region

  def initialize(settings, calls)
    @settings = settings
    @calls = calls.reject(&:internal?)
    @costs = Outsider::Voice::CallCosts.new(settings)
  end

  def to_h
    { regions: regions, costs: costs, by_ddd: by_ddd, by_branch: by_branch }
  end

  def cost_of(calls)
    calls.sum { |call| cost(call) }.round(2)
  end

  private

  def cost(call)
    (@cost_cache ||= {})[call.id] ||= @costs.cost(call)
  end

  def region(call)
    (@region_cache ||= {})[call.id] ||= Region.of(call.customer_number) || {}
  end

  def summary(calls)
    { calls: calls.size, inbound: calls.count(&:inbound?), outbound: calls.count(&:outbound?), answered: calls.count(&:answered?),
      talk_seconds: calls.sum { |call| call.answered? ? call.talk_seconds.to_i : 0 }, cost: cost_of(calls) }
  end

  # { states: { 'GO' => {...} }, international: {...}, unknown: n }
  def regions
    groups = @calls.group_by { |call| region(call)[:state] }
    states = groups.except(nil, Region::INTERNATIONAL).transform_values { |calls| summary(calls) }
    { states: states, international: summary(groups.fetch(Region::INTERNATIONAL, [])), unknown: groups.fetch(nil, []).size }
  end

  def costs
    total = cost_of(@calls)
    { total: total, outbound: cost_of(@calls.select(&:outbound?)), inbound: cost_of(@calls.select(&:inbound?)), by_kind: by_kind,
      billing: @settings.costs['billing'], configured: configured? }.merge(averages(total))
  end

  # custo médio por ligação que custou e por minuto cobrado
  def averages(total)
    paid = @calls.select { |call| cost(call).positive? }
    minutes = paid.sum { |call| call.talk_seconds.to_i } / 60.0
    { paid_calls: paid.size, per_call: paid.empty? ? 0 : (total / paid.size).round(2),
      per_minute: minutes.zero? ? 0 : (total / minutes).round(4) }
  end

  def by_kind
    @calls.group_by { |call| @costs.kind(call) }.transform_values do |calls|
      { calls: calls.size, talk_seconds: calls.sum { |call| call.answered? ? call.talk_seconds.to_i : 0 }, cost: cost_of(calls) }
    end
  end

  def configured?
    @settings.costs['rates'].values.any? { |rate| rate.values.any?(&:positive?) }
  end

  # DDD do cliente, os que mais aparecem primeiro
  def by_ddd
    rows = @calls.group_by { |call| region(call)[:ddd] }.except(nil).map do |ddd, calls|
      summary(calls).merge(ddd: ddd, state: Region::BY_DDD[ddd])
    end
    rows.sort_by { |row| [-row[:calls], row[:ddd]] }
  end

  # filial do vendedor da ligação; ligação sem vendedor (perdida) ou de quem não tem filial fica em "sem filial"
  def by_branch
    return [] if @settings.branches.empty?

    groups = @calls.group_by { |call| branch_of[call.user_id.to_s] }
    rows = @settings.branches.map { |branch| branch_row(branch, groups.fetch(branch['id'], [])) }
    rest = groups.except(*@settings.branches.pluck('id')).values.flatten
    rows << summary(rest).merge(id: nil, name: nil, people: nil) if rest.any?
    rows
  end

  def branch_row(branch, calls)
    summary(calls).merge(id: branch['id'], name: branch['name'], people: branch_of.count { |_id, id| id == branch['id'] })
  end

  def branch_of
    @branch_of ||= @settings.data['agents'].transform_values { |agent| agent['branch'] }
  end
end
