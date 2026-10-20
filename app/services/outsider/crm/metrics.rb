# OUTSIDER: indicadores do topo do Kanban. Valor e previsão ponderada contam os negócios
# abertos; conversão e tempo médio contam os fechados dentro do período escolhido.
class Outsider::Crm::Metrics
  PERIODS = { 'month' => :beginning_of_month, 'quarter' => :beginning_of_quarter, 'year' => :beginning_of_year }.freeze
  # valor ponderado: a chance do próprio negócio ou, sem ela, a da etapa (a conta precisa de joins(:stage))
  WEIGHTED_SQL = 'outsider_crm_opportunities.value_cents * COALESCE(outsider_crm_opportunities.probability, ' \
                 'outsider_crm_stages.probability) / 100.0'.freeze
  DAYS_TO_CLOSE_SQL = 'EXTRACT(EPOCH FROM (outsider_crm_opportunities.closed_at - outsider_crm_opportunities.created_at))'.freeze

  def self.weighted(scope)
    scope.joins(:stage).sum(Arel.sql(WEIGHTED_SQL)).round
  end

  def self.average_days(scope)
    seconds = scope.average(Arel.sql(DAYS_TO_CLOSE_SQL))
    seconds && (seconds.to_f / 1.day).round(1)
  end

  def initialize(scope, period: 'month')
    @scope = scope
    @period = PERIODS.key?(period) ? period : 'month'
  end

  def to_h
    open = @scope.open
    closed = @scope.where(status: [:won, :lost], closed_at: since..)
    won = closed.won
    {
      period: @period,
      since: since.to_date,
      open_count: open.count,
      open_value_cents: open.sum(:value_cents),
      weighted_value_cents: self.class.weighted(open),
      won_count: won.count,
      won_value_cents: won.sum(:value_cents),
      lost_count: closed.lost.count,
      conversion_rate: closed.count.zero? ? nil : (won.count * 100.0 / closed.count).round(1),
      average_days_to_win: self.class.average_days(won)
    }
  end

  private

  def since
    @since ||= Time.zone.now.public_send(PERIODS.fetch(@period))
  end
end
