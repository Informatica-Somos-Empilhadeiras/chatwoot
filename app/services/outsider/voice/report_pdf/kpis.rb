# OUTSIDER: os números do relatório de ligações em PDF (Entrega 24; ver Outsider::Voice::ReportPdf): três
# linhas de quatro quadros (volume, taxas, tempos), cada um com a diferença para o período anterior.
module Outsider::Voice::ReportPdf::Kpis
  BOX_HEIGHT = 56
  ROW_HEIGHT = 62
  GAP = 6

  private

  def kpis
    width = (@pdf.bounds.width - (GAP * 3)) / 4
    [volume_kpis, rate_kpis, time_kpis].each do |row|
      top = @pdf.cursor
      row.each_with_index { |item, index| kpi_box(item, index * (width + GAP), top, width) }
      @pdf.move_cursor_to top - ROW_HEIGHT
    end
    @pdf.move_down 8
  end

  def volume_kpis
    [kpi('Ligações', summary[:total], :total),
     kpi('Recebidas', summary[:inbound], :inbound, "#{summary[:inbound_answered]} atendidas · #{summary[:missed]} perdidas"),
     kpi('Feitas', summary[:outbound], :outbound, "#{summary[:outbound_answered]} atendidas pelo cliente"),
     kpi('Entre ramais', summary[:internal], :internal)]
  end

  def rate_kpis
    [kpi('Taxa de atendimento', percent(summary[:answer_rate]), :answer_rate, 'recebidas atendidas'),
     kpi('Taxa de contato', percent(summary[:contact_rate]), :contact_rate, 'feitas atendidas pelo cliente'),
     kpi('Nível de serviço', percent(summary[:service_level]), :service_level, "atendidas em até #{@data[:service_seconds]} s"),
     kpi('Clientes', summary[:customers], :customers, 'números diferentes')]
  end

  def time_kpis
    returned = summary[:returned].positive? ? "em #{duration(summary[:average_return])} em média" : ''
    [kpi('Tempo médio de conversa', duration(summary[:average_talk]), :average_talk),
     kpi('Tempo médio para atender', duration(summary[:average_answer]), :average_answer),
     kpi('Tempo total em ligação', talk_time(summary[:talk_seconds]), :talk_seconds),
     kpi('Perdidas retornadas', "#{summary[:returned]} de #{summary[:missed]}", nil, returned)]
  end

  def kpi(label, value, key, hint = '')
    { label: label, value: value.to_s, hint: hint, delta: key && delta(key) }
  end

  def kpi_box(item, left, top, width)
    @pdf.fill_color self.class::BOX
    @pdf.fill_rounded_rectangle [left, top], width, BOX_HEIGHT, 4
    @pdf.fill_color self.class::INK
    @pdf.bounding_box([left + 8, top - 7], width: width - 16, height: BOX_HEIGHT - 10) { kpi_text(item) }
  end

  def kpi_text(item)
    muted = self.class::MUTED
    @pdf.text clean(item[:label]), size: 7.5, color: muted
    @pdf.text clean(item[:value]), size: 15, style: :bold
    @pdf.text clean(item[:hint]), size: 7, color: muted if item[:hint].present?
    @pdf.text clean(item[:delta]), size: 7, color: muted if item[:delta]
  end

  # diferença com o período anterior: em pontos (taxas) ou em %
  def delta(key)
    now = summary[key]
    before = previous[key]
    return if now.nil? || before.nil?
    return "#{format('%+.1f', now - before).tr('.', ',')} pontos" if key.to_s.end_with?('_rate', '_level')
    return 'sem base anterior' if before.zero?

    "#{format('%+d', ((now - before) * 100.0 / before).round)}% no período anterior"
  end
end
