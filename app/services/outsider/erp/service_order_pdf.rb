# OUTSIDER: PDF do relatório de uma OS igual à "Impressão de Ordem de Serviço - Check-List" que o kanban de KPI do Mais
# Prático emite. Fontes, tamanhos, cores, posições e espaçamentos foram medidos no PDF da OS 850 deles (ver Layout): o
# cabeçalho se repete em toda página (12pt mais alto a partir da 2ª), os dados vêm em rótulo/valor, check-in/out e
# produtos em tabela (Tables), a avaliação técnica numa caixa e o checklist com as fotos em grade (Checklist). Só
# desenha o hash do Outsider::Erp::ServiceOrderReport. As medidas contam do topo da página, como no original.
class Outsider::Erp::ServiceOrderPdf
  include Outsider::Erp::QuotePdfText
  include Outsider::Erp::ServiceOrderPdf::Layout
  include Outsider::Erp::ServiceOrderPdf::Drawing
  include Outsider::Erp::ServiceOrderPdf::Tables
  include Outsider::Erp::ServiceOrderPdf::Checklist

  Prawn::Fonts::AFM.hide_m17n_warning = true

  def initialize(report)
    @report = report
  end

  def filename
    customer = @report.dig('cliente', 'nome').to_s.parameterize(separator: ' ').upcase.first(50)
    "OS #{@report['numero']} - #{customer}.pdf".squeeze(' ')
  end

  def render
    @pdf = Prawn::Document.new(page_size: 'A4', margin: 0, info: { Title: clean(filename.delete_suffix('.pdf')), Creator: 'Chat' })
    @pdf.default_kerning(false)
    start_page(first: true)
    customer_and_equipment
    service
    table(EVENTS, @report['eventos'].map { |event| event.values_at('tipo', 'observacoes', 'check_in', 'check_out') })
    evaluation
    table(PRODUCTS, @report['produtos'].map { |item| [item['codigo'], item['descricao'], item['unidade'], qty(item['quantidade'])] })
    checklist
    page_numbers
    @pdf.render
  end

  private

  # ---- página e cabeçalho ----

  def start_page(first: false)
    @pdf.start_new_page unless first
    top = @pdf.page_number == 1 ? 24.72 : 12.72
    header(top)
    @y = top + 89.4
    @after = :header
  end

  # nova página; devolve onde fica o 1º elemento dela (a distância vem de quem chama, a partir da linha azul)
  def page_break(offset)
    start_page
    @y + offset
  end

  def header(top)
    emitter = @report['emitente'].to_h
    logo(emitter['logo'], top)
    letterhead(emitter, top)
    write_right([['ORDEM DE SERVIÇO: ', :normal], [@report['numero'].to_s, :bold]], top + 67.68)
    write_right([['Data: ', :normal], [Time.zone.today.strftime('%d/%m/%Y'), :bold]], top + 78.12)
    bar(LEFT, top + 87.84, [RIGHT - LEFT, 1.56], BLUE)
  end

  # ao lado do logo: nome em azul, telefone, e-mail e o título
  def letterhead(emitter, top)
    write(emitter['nome'], [127.2, top + 12.72], size: 14, style: :bold, color: BLUE)
    write(label('Telefone', emitter['fone']), [127.2, top + 25.68], style: :bold)
    write(label('E-mail', emitter['email']), [127.2, top + 36.84], style: :bold)
    write('Impressão de Ordem de Serviço - Check-List', [127.2, top + 61.8], size: 14, style: :bold)
  end

  # o logo ocupa a caixa inteira (o deles é esticado para 90,36 x 80,40)
  def logo(bytes, top)
    @pdf.image(StringIO.new(bytes), at: [LEFT, PAGE_HEIGHT - top], width: 90.36, height: 80.4) if bytes.present?
  rescue Prawn::Errors::UnsupportedImageType, StandardError
    nil
  end

  # "Página 1 de 2" no alto, em Times 8 preto, em toda página
  def page_numbers
    total = @pdf.page_count
    (1..total).each do |number|
      @pdf.go_to_page(number)
      text = clean("Página #{number} de #{total}")
      @pdf.font('Times-Roman') do
        @pdf.fill_color('000000')
        @pdf.draw_text(text, at: [298.35 - (@pdf.width_of(text, size: 8) / 2), PAGE_HEIGHT - 9.0], size: 8)
      end
    end
  end

  # ---- campos ----

  def customer_and_equipment
    customer = @report['cliente'].to_h
    equipment = @report['equipamento'].to_h
    section_title('Dados do cliente e equipamento')
    field_row([['Cliente', customer['nome']], ['Descrição', equipment['descricao']]], COLUMNS)
    field_row([['CNPJ', customer['documento']], ['Marca', equipment['marca']]], COLUMNS)
    field_row([['Endereço', customer['endereco']], ['Modelo', equipment['modelo']]], COLUMNS)
    field_row([['Cidade', customer['cidade']], ['Nº série', equipment['serie']], ['Horímetro', equipment['horimetro']]], COLUMNS_WITH_HOURS)
  end

  def service
    data = @report['servico'].to_h
    section_title('Dados do serviço')
    [['Tipo de atendimento', data['tipo_atendimento']], ['Classificação', data['classificacao']],
     ['Técnico principal', data['tecnico']], ['Defeitos mencionados', data['defeitos']]].each { |pair| field_row([pair], FULL_ROW) }
  end

  def section_title(text)
    baseline = @y + (@after == :header ? 29.28 : 30.0)
    baseline = page_break(29.28) if baseline + 18.72 + LINE > BOTTOM
    write_center(text.upcase, baseline)
    @y = baseline
    @after = :title
  end

  # uma linha de campos lado a lado (rótulo em cima, valor embaixo); a seguinte parte do valor mais comprido. No
  # original o valor fica 11,31 abaixo do rótulo e a linha seguinte 18,75 abaixo do valor (18,72 logo após o título).
  def field_row(pairs, columns)
    values = pairs.each_with_index.map { |(_, value), index| wrap(value, columns[index][1]) }
    extra = LINE * (values.map(&:size).max - 1)
    baseline = @y + (@after == :value ? 18.75 : 18.72)
    baseline = page_break(29.28) if baseline + 11.31 + extra > BOTTOM
    pairs.each_with_index { |(name, _), index| field(name, values[index], columns[index][0], baseline) }
    @y = baseline + 11.31 + extra
    @after = :value
  end

  def field(name, lines, left, baseline)
    write(name.upcase, [left, baseline], style: :bold, color: LABEL)
    lines.each_with_index { |line, row| write(line, [left, baseline + 11.31 + (LINE * row)]) }
  end

  # ---- avaliação técnica: texto numa caixa de traço cinza ----

  def evaluation
    lines = wrap(@report['avaliacao'].to_s.gsub("\r\n", "\n"), 530.28)
    return if lines.join.blank?

    baseline = @y + (@after == :table ? 24.0 : 30.0)
    baseline = page_break(29.28) if baseline + 6.35 + 20.65 + LINE + 21.25 > BOTTOM
    write_center('AVALIAÇÃO TÉCNICA', baseline)
    @y = evaluation_box(lines, baseline + 6.35)
    @after = :box
  end

  # escreve as linhas a partir do topo da caixa; se não couberem, fecha a caixa e continua na página seguinte
  def evaluation_box(lines, box_top)
    line_y = box_top + 20.65
    lines.each_with_index do |line, index|
      if index.positive? && line_y + 21.25 > BOTTOM
        frame(box_top, line_y - EVALUATION_LINE + 21.25)
        box_top = page_break(12.0)
        line_y = box_top + 20.65
      end
      write(line, [33.25, line_y])
      line_y += EVALUATION_LINE
    end
    frame(box_top, line_y - EVALUATION_LINE + 21.25)
  end

  # devolve o fundo da caixa (traço de 0,84 pelo centro, de 25,35 a 571,43)
  def frame(top, bottom)
    @pdf.stroke_color(GRID)
    @pdf.line_width(BORDER)
    @pdf.stroke_rectangle([25.35, PAGE_HEIGHT - top], 546.08, bottom - top)
    bottom
  end
end
