# OUTSIDER: ligações por hora no relatório em PDF (Entrega 24; ver Outsider::Voice::ReportPdf): barras
# empilhadas por tipo (cores de SERIES), do expediente (8h às 18h) e das horas que tiveram ligação fora dele,
# com o total em cima de cada barra.
module Outsider::Voice::ReportPdf::HourChart
  CHART_HEIGHT = 110
  LEGEND_STEP = 100

  private

  def hour_chart
    title('Ligações por hora')
    legend
    top = @pdf.cursor
    hours = chart_hours
    slot = @pdf.bounds.width / hours.count
    hours.each_with_index { |hour, index| hour_bar(@data[:by_hour][hour], (index * slot) + (slot * 0.2), slot * 0.6, top - CHART_HEIGHT) }
    baseline(top - CHART_HEIGHT)
  end

  def baseline(at)
    @pdf.fill_color self.class::INK
    @pdf.stroke_color self.class::LINE
    @pdf.stroke_horizontal_line 0, @pdf.bounds.width, at: at
    @pdf.move_cursor_to at - 20
  end

  def chart_hours
    busy = @data[:by_hour].select { |row| hour_total(row).positive? }.pluck(:hour)
    ([8] + busy).min..([18] + busy).max
  end

  def hour_total(row)
    self.class::SERIES.keys.sum { |key| row[key] }
  end

  def bar_scale
    @bar_scale ||= CHART_HEIGHT / [@data[:by_hour].map { |row| hour_total(row) }.max.to_i, 1].max.to_f
  end

  def hour_bar(row, left, width, baseline)
    bottom = baseline
    self.class::SERIES.each do |key, color|
      height = row[key] * bar_scale
      next if height.zero?

      @pdf.fill_color color
      @pdf.fill_rectangle [left, bottom + height], width, height
      bottom += height
    end
    @pdf.fill_color self.class::MUTED
    @pdf.draw_text hour_total(row).to_s, at: [left, bottom + 2], size: 6 if hour_total(row).positive?
    @pdf.draw_text "#{row[:hour]}h", at: [left, baseline - 9], size: 6.5
  end

  def legend
    y = @pdf.cursor
    self.class::SERIES.each_with_index do |(key, color), index|
      x = index * LEGEND_STEP
      @pdf.fill_color color
      @pdf.fill_rectangle [x, y - 1], 7, 7
      @pdf.fill_color self.class::MUTED
      @pdf.draw_text clean(self.class::SERIES_LABELS[key]), at: [x + 10, y - 7], size: 7.5
    end
    @pdf.fill_color self.class::INK
    @pdf.move_down 14
  end
end
