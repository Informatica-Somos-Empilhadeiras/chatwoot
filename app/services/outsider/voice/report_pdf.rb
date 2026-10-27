# OUTSIDER: relatório de ligações em PDF (Entrega 24), com os mesmos números do painel da Telefonia
# (Outsider::Voice::Wallboard) no período escolhido: os indicadores com a comparação com o período anterior,
# ligações por hora, dia a dia, a equipe (gestor vendo todos) e a duração das conversas. A4, fontes do próprio
# PDF (Helvetica): o texto passa por clean (Windows-1252).
class Outsider::Voice::ReportPdf
  include Outsider::Voice::ReportPdf::Kpis
  include Outsider::Voice::ReportPdf::HourChart

  MARGIN = 36
  INK = '1F2937'.freeze
  MUTED = '6B7280'.freeze
  LINE = 'E5E7EB'.freeze
  BOX = 'F5F7FA'.freeze
  SERIES = { inbound_answered: '12A594', missed: 'E5484D', outbound: '0090FF', internal: '9CA3AF' }.freeze
  SERIES_LABELS = { inbound_answered: 'Recebidas atendidas', missed: 'Perdidas', outbound: 'Feitas', internal: 'Entre ramais' }.freeze

  Prawn::Fonts::AFM.hide_m17n_warning = true

  def initialize(wallboard, account)
    @board = wallboard
    @data = wallboard.to_h
    @account = account
    @zone = wallboard.period.zone
  end

  def filename
    "relatorio-ligacoes-#{@data[:period][:from]}-a-#{@data[:period][:to]}.pdf"
  end

  def render
    @pdf = Prawn::Document.new(page_size: 'A4', margin: MARGIN, info: { Title: 'Relatorio de ligacoes', Creator: 'Telefonia' })
    @pdf.font('Helvetica', size: 9)
    @pdf.fill_color INK
    header
    kpis
    hour_chart
    timeline_table
    team_table
    talk_table
    footer
    @pdf.render
  end

  private

  def summary
    @data[:summary]
  end

  def previous
    @data[:previous]
  end

  def header
    @pdf.text clean('Relatório de ligações'), size: 18, style: :bold
    who = @board.user&.name || 'Equipe toda'
    period = @board.period
    line = "#{who}  ·  #{period.label}  ·  #{@account.name}"
    @pdf.text clean(line), size: 10, color: MUTED
    compare = "Comparação com o período anterior: #{period.label(period.previous)}"
    @pdf.text clean(compare), size: 8, color: MUTED
    @pdf.move_down 14
  end

  def timeline_table
    timeline = @data[:timeline]
    return unless timeline

    title(timeline[:unit] == 'month' ? 'Mês a mês' : 'Dia a dia')
    rows = timeline[:rows].reject { |row| row[:future] }.map do |row|
      date = timeline[:unit] == 'month' ? row[:date].strftime('%m/%Y') : "#{row[:date].strftime('%d/%m')} #{weekday(row[:date])}"
      [date, row[:total], row[:inbound_answered], row[:missed], row[:outbound], row[:internal], talk_time(row[:talk_seconds]),
       percent(row[:answer_rate])]
    end
    table(['', 'Ligações', 'Receb. atendidas', 'Perdidas', 'Feitas', 'Entre ramais', 'Em ligação', 'Taxa atend.'], rows)
  end

  def team_table
    agents = @data[:agents]
    return if agents.blank? || @data[:user_id]

    title('Equipe')
    rows = agents.sort_by { |agent| -agent[:total] }.map do |agent|
      [agent[:name], agent[:extension], agent[:total], agent[:outbound], agent[:outbound_answered], percent(agent[:contact_rate]),
       agent[:inbound_answered], talk_time(agent[:talk_seconds]), duration(agent[:average_talk])]
    end
    table(['Vendedor', 'Ramal', 'Ligações', 'Feitas', 'Atend. cliente', 'Contato', 'Receb. atendidas', 'Em ligação', 'Média'], rows)
  end

  def talk_table
    return if summary[:total].zero?

    title('Duração das conversas')
    labels = ['até 1 min', '1 a 3 min', '3 a 5 min', '5 a 10 min', '10 a 20 min', 'mais de 20 min']
    table(labels, [@data[:talk_buckets].pluck(:count)])
  end

  def table(headers, rows)
    @pdf.table([headers.map { |text| clean(text) }] + rows.map { |row| row.map { |cell| clean(cell.to_s) } },
               header: true, width: @pdf.bounds.width,
               cell_style: { size: 7.5, padding: [3, 4], border_color: LINE, border_widths: [0, 0, 0.5, 0] }) do |grid|
      grid.row(0).font_style = :bold
      grid.row(0).text_color = MUTED
      grid.columns(1..(headers.size - 1)).align = :right
    end
    @pdf.move_down 14
  end

  def title(text)
    @pdf.start_new_page if @pdf.cursor < 160
    @pdf.text clean(text), size: 11, style: :bold
    @pdf.move_down 6
  end

  def footer
    stamp = "Gerado em #{I18n.l(Time.current.in_time_zone(@zone), format: '%d/%m/%Y %H:%M')} (#{@zone.tzinfo.name})"
    @pdf.number_pages clean("#{stamp}  ·  página <page> de <total>"), at: [0, -6], size: 7, color: MUTED
  end

  def weekday(date)
    %w[dom seg ter qua qui sex sáb][date.wday]
  end

  def percent(value)
    value.nil? ? '—' : "#{format('%.1f', value).tr('.', ',')}%"
  end

  def duration(seconds)
    seconds = seconds.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    hours.positive? ? format('%<h>d:%<m>02d:%<s>02d', h: hours, m: minutes, s: seconds % 60) : format('%<m>d:%<s>02d', m: minutes, s: seconds % 60)
  end

  def talk_time(seconds)
    minutes = (seconds.to_i / 60.0).round
    minutes >= 60 ? "#{minutes / 60} h #{minutes % 60} min" : "#{minutes} min"
  end

  def clean(text)
    text.to_s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '').encode('UTF-8')
  end
end
