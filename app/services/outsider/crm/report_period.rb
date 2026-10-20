# OUTSIDER: período dos relatórios do CRM. "Este mês", "este trimestre" e "este ano" começam no
# mesmo dia que os indicadores do Kanban (Outsider::Crm::Metrics), para os números baterem.
class Outsider::Crm::ReportPeriod
  KEYS = %w[month last_month quarter year last_12_months].freeze

  attr_reader :key

  def initialize(key)
    @key = KEYS.include?(key) ? key : 'month'
  end

  def range
    @range ||= begin
      now = Time.zone.now
      case @key
      when 'last_month' then now.prev_month.all_month
      when 'quarter' then now.all_quarter
      when 'year' then now.all_year
      when 'last_12_months' then (now - 11.months).beginning_of_month..now.end_of_month
      else now.all_month
      end
    end
  end

  def as_json(*)
    { key: @key, from: range.begin.to_date, to: [range.end, Time.zone.now].min.to_date }
  end
end
