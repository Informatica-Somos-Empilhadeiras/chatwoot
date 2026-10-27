# OUTSIDER: período dos números da Telefonia (Entrega 24): painel, exportações e relatório em PDF. Hoje, ontem,
# esta semana, semana passada, este mês, mês passado ou de uma data a outra, sempre no fuso da telefonia
# (Telefonia > Configurações; Brasília se não escolhido), nunca no do navegador nem no do servidor (UTC).
#
# previous: o mesmo pedaço do período anterior, para comparar. Período que ainda está correndo compara até o
# mesmo ponto: hoje até agora com ontem até a mesma hora, este mês até hoje com o mês passado até o mesmo dia.
class Outsider::Voice::Period
  KEYS = %w[today yesterday week last_week month last_month custom].freeze
  CURRENT = %w[today week month].freeze
  MAX_DAYS = 366
  # até este número de dias os gráficos mostram dia a dia; acima, mês a mês
  DAILY_LIMIT = 62

  attr_reader :key, :zone

  def initialize(zone, key, from: nil, to: nil)
    @zone = zone
    @from = parse(from)
    @to = parse(to)
    @key = KEYS.include?(key.to_s) ? key.to_s : 'today'
    @key = 'today' if @key == 'custom' && !(@from && @to)
  end

  RANGES = {
    'today' => ->(now) { now.all_day }, 'yesterday' => ->(now) { (now - 1.day).all_day },
    'week' => ->(now) { now.all_week }, 'last_week' => ->(now) { (now - 1.week).all_week },
    'month' => ->(now) { now.all_month }, 'last_month' => ->(now) { now.prev_month.all_month }
  }.freeze

  def range
    @range ||= key == 'custom' ? custom_range : RANGES.fetch(key).call(now)
  end

  def previous
    @previous ||= if CURRENT.include?(key)
                    ongoing_previous
                  elsif key == 'last_month'
                    range.begin.prev_month.all_month
                  else
                    length = days.size
                    (range.begin - length.days)..(range.begin - 1.second)
                  end
  end

  # até onde o período já aconteceu (período que ainda corre termina agora)
  def until_now
    CURRENT.include?(key) ? range.begin..now : range
  end

  def from_date
    range.begin.to_date
  end

  def to_date
    range.end.to_date
  end

  def days
    (from_date..to_date).to_a
  end

  def daily?
    days.size <= DAILY_LIMIT
  end

  def single_day?
    days.size == 1
  end

  def local(time)
    time.in_time_zone(zone)
  end

  def label(dates = from_date..to_date)
    first = dates.begin.to_date.strftime('%d/%m/%Y')
    last = dates.end.to_date.strftime('%d/%m/%Y')
    first == last ? first : "#{first} a #{last}"
  end

  def future?(date)
    date > now.to_date
  end

  def as_json(*)
    { key: key, from: from_date, to: to_date, previous_from: previous.begin.to_date, previous_to: previous.end.to_date,
      daily: daily?, single_day: single_day?, zone: zone.tzinfo.name }
  end

  private

  def now
    @now ||= Time.current.in_time_zone(zone)
  end

  def parse(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def custom_range
    from, to = [@from, @to].sort
    to = [to, from + (MAX_DAYS - 1).days].min
    from.in_time_zone(zone).beginning_of_day..to.in_time_zone(zone).end_of_day
  end

  # o período anterior até o mesmo ponto; num mês mais curto, no máximo até o fim dele
  def ongoing_previous
    elapsed = now - range.begin
    start = case key
            when 'today' then range.begin - 1.day
            when 'week' then range.begin - 1.week
            else range.begin.prev_month
            end
    finish = [start + elapsed, key == 'month' ? start.end_of_month : start + elapsed].min
    start..finish
  end
end
