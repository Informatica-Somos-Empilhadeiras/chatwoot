# OUTSIDER: números da aba Relatórios. Tudo sai de agregações no banco (COUNT/SUM agrupados), sem
# carregar negócio por negócio, para não pesar no banco de produção.
#
# Regras (as mesmas dos indicadores do Kanban):
# - aberto, valor e previsão ponderada: retrato de agora, só negócios abertos;
# - ganhos, perdidos e encaminhados: fechados dentro do período (closed_at);
# - o perdido que o repasse em sequência mandou para outra unidade conta nos perdidos (com o motivo
#   da perda) e também nos encaminhados (saiu da unidade); não entra nos motivos de encaminhamento;
# - conversão: ganhos / (ganhos + perdidos). Encaminhado não entra: ele continua noutra unidade;
# - previsão: negócios abertos pela data prevista de fechamento, em valor cheio e ponderado.
class Outsider::Crm::Report
  FORECAST_MONTHS = 6
  COUNT_SQL = Arel.sql('COUNT(*)')
  VALUE_SQL = Arel.sql('COALESCE(SUM(outsider_crm_opportunities.value_cents), 0)')
  WEIGHTED_SUM_SQL = Arel.sql("COALESCE(SUM(#{Outsider::Crm::Metrics::WEIGHTED_SQL}), 0)")

  def initialize(scope, period:)
    @scope = scope
    @period = period
  end

  def to_h
    {
      period: @period.as_json,
      summary: summary,
      forecast: forecast,
      units: breakdown(:business_unit_id, Outsider::Crm::BusinessUnit),
      owners: breakdown(:owner_id, User),
      lost_reasons: reasons(closed.lost),
      forward_reasons: reasons(closed.forwarded)
    }
  end

  private

  def open
    @scope.open
  end

  def closed
    @scope.where(status: [:won, :lost, :forwarded], closed_at: @period.range)
  end

  def created
    @scope.where(created_at: @period.range)
  end

  def chain_handoffs
    closed.lost.where(id: Outsider::Crm::Forward.select(:from_opportunity_id))
  end

  def summary
    open_totals(open).merge(created_totals).merge(closed_totals)
  end

  def open_totals(scope)
    count, value, weighted = scope.joins(:stage).pick(COUNT_SQL, VALUE_SQL, WEIGHTED_SUM_SQL)
    { open_count: count, open_value_cents: value.to_i, weighted_value_cents: weighted.to_f.round }
  end

  def created_totals
    count, value = created.pick(COUNT_SQL, VALUE_SQL)
    { created_count: count, created_value_cents: value.to_i, received_count: created.where.not(forwarded_from_id: nil).count }
  end

  def closed_totals
    by_status = closed.group(:status).pluck(:status, COUNT_SQL, VALUE_SQL).to_h { |status, count, value| [status, [count, value.to_i]] }
    won_count, won_value = by_status.fetch('won', [0, 0])
    lost_count, lost_value = by_status.fetch('lost', [0, 0])
    {
      won_count: won_count, won_value_cents: won_value, lost_count: lost_count, lost_value_cents: lost_value,
      forwarded_count: by_status.fetch('forwarded', [0]).first + chain_handoffs.count, conversion_rate: rate(won_count, won_count + lost_count),
      average_ticket_cents: won_count.zero? ? nil : won_value / won_count,
      average_days_to_win: Outsider::Crm::Metrics.average_days(closed.won)
    }
  end

  # Atrasados (data prevista já passou), os próximos meses, depois disso e sem data
  def forecast
    today = Time.zone.today
    bucket = forecast_bucket_sql(today)
    rows = open.joins(:stage).group(bucket).pluck(bucket, COUNT_SQL, VALUE_SQL, WEIGHTED_SUM_SQL).index_by(&:first)
    months = Array.new(FORECAST_MONTHS) { |index| (today.beginning_of_month >> index).strftime('%Y-%m') }
    (['overdue'] + months + %w[later no_date]).map do |key|
      _key, count, value, weighted = rows[key]
      { key: key, count: count.to_i, value_cents: value.to_i, weighted_value_cents: weighted.to_f.round }
    end
  end

  def forecast_bucket_sql(today)
    Arel.sql(Outsider::Crm::Opportunity.sanitize_sql_array([<<~SQL.squish, today, today.beginning_of_month >> FORECAST_MONTHS]))
      CASE WHEN outsider_crm_opportunities.expected_close_on IS NULL THEN 'no_date'
           WHEN outsider_crm_opportunities.expected_close_on < ? THEN 'overdue'
           WHEN outsider_crm_opportunities.expected_close_on >= ? THEN 'later'
           ELSE to_char(outsider_crm_opportunities.expected_close_on, 'YYYY-MM') END
    SQL
  end

  # Uma linha por unidade ou por responsável (id nil = sem responsável)
  def breakdown(column, model)
    rows = Hash.new { |hash, id| hash[id] = empty_row(id) }
    add_open(rows, column)
    add_closed(rows, column)
    created.where.not(forwarded_from_id: nil).group(column).count.each { |id, count| rows[id][:received_count] = count }
    finish_rows(rows.values, model)
  end

  def add_open(rows, column)
    open.joins(:stage).group(column).pluck(column, COUNT_SQL, VALUE_SQL, WEIGHTED_SUM_SQL).each do |id, count, value, weighted|
      rows[id].merge!(open_count: count, open_value_cents: value.to_i, weighted_value_cents: weighted.to_f.round)
    end
  end

  def add_closed(rows, column)
    closed.group(column, :status).pluck(column, :status, COUNT_SQL, VALUE_SQL).each do |id, status, count, value|
      rows[id].merge!("#{status}_count": count, "#{status}_value_cents": value.to_i)
    end
    chain_handoffs.group(column).pluck(column, COUNT_SQL, VALUE_SQL).each do |id, count, value|
      rows[id][:forwarded_count] += count
      rows[id][:forwarded_value_cents] += value.to_i
    end
  end

  def empty_row(id)
    { id: id, open_count: 0, open_value_cents: 0, weighted_value_cents: 0, won_count: 0, won_value_cents: 0,
      lost_count: 0, lost_value_cents: 0, forwarded_count: 0, forwarded_value_cents: 0, received_count: 0 }
  end

  # Nome, conversão e ordem alfabética, com "sem responsável" no fim
  def finish_rows(rows, model)
    names = model.where(id: rows.filter_map { |row| row[:id] }).pluck(:id, :name).to_h
    rows.each do |row|
      row[:name] = names[row[:id]]
      row[:conversion_rate] = rate(row[:won_count], row[:won_count] + row[:lost_count])
    end
    rows.sort_by { |row| [row[:name] ? 0 : 1, row[:name].to_s.downcase] }
  end

  # Motivo nil = fechado sem motivo (a conta ainda não tinha motivos cadastrados)
  def reasons(scope)
    rows = scope.group(:lost_reason_id).pluck(:lost_reason_id, COUNT_SQL, VALUE_SQL)
    names = Outsider::Crm::LostReason.where(id: rows.filter_map(&:first)).pluck(:id, :name).to_h
    rows.map { |id, count, value| { id: id, name: names[id], count: count, value_cents: value.to_i } }
        .sort_by { |row| [-row[:count], row[:name].to_s] }
  end

  def rate(part, total)
    total.zero? ? nil : (part * 100.0 / total).round(1)
  end
end
