# OUTSIDER: bloco "Horário de atendimento" do bot. hours = { '0' (domingo) .. '6' (sábado) =>
# { 'enabled', 'start' => 'HH:MM', 'end' => 'HH:MM' } } no fuso escolhido. Fim antes do começo
# (ex.: 22:00 às 06:00) atravessa a meia-noite.
class Outsider::Bot::Hours
  def initialize(data, now: Time.current)
    @hours = data['hours'].to_h
    zone = ActiveSupport::TimeZone[data['timezone'].to_s] || ActiveSupport::TimeZone[Outsider::Bot::Graph::DEFAULT_TIMEZONE]
    @now = now.in_time_zone(zone)
  end

  def open_now?
    today = @hours[@now.wday.to_s].to_h
    yesterday = @hours[((@now.wday - 1) % 7).to_s].to_h
    minute = (@now.hour * 60) + @now.min
    inside?(today, minute) || overnight_tail?(yesterday, minute)
  end

  private

  def inside?(day, minute)
    return false unless day['enabled']

    start = minutes(day['start'])
    finish = minutes(day['end'])
    start <= finish ? minute.between?(start, finish - 1) : minute >= start
  end

  # o expediente de ontem que passou da meia-noite
  def overnight_tail?(day, minute)
    return false unless day['enabled']

    start = minutes(day['start'])
    finish = minutes(day['end'])
    start > finish && minute < finish
  end

  def minutes(value)
    hour, minute = value.to_s.split(':').map(&:to_i)
    (hour.to_i * 60) + minute.to_i
  end
end
