# OUTSIDER: PDF do orçamento de peças e serviços no modelo do relatório do Mais Prático (orçamento 3309): cabeçalho com
# logo e dados do emitente, cliente, linhas com NCM/CST/ICMS, condições de pagamento, Demais Condições, totais,
# observações e assinatura do vendedor. Só desenha o hash do Outsider::Erp::QuoteReport (orçamento do ERP) ou do
# Outsider::Erp::BudgetPreview (rascunho, marcado como prévia). Fontes do próprio PDF: o texto sai em Windows-1252.
class Outsider::Erp::QuotePdf
  include Outsider::Erp::QuotePdfText
  MARGIN = 28
  FONT_SIZE = 8
  LINE_COLUMNS = [
    ['Código', 38, :left], ['Descrição das Mercadorias', nil, :left], ['Un.', 24, :left], ['Qtd.', 28, :right], ['NCM', 50, :left],
    ['CST', 26, :left], ['ICMS', 30, :right], ['Vr ICMS', 42, :right], ['Desc. R$', 44, :right], ['Unit. R$', 50, :right],
    ['Total R$', 52, :right]
  ].freeze

  Prawn::Fonts::AFM.hide_m17n_warning = true

  def initialize(report)
    @report = report
  end

  def filename
    customer = @report.dig('cliente', 'nome').to_s.parameterize(separator: ' ').upcase.first(50)
    "#{@report['previa'] ? 'PREVIA ORCAMENTO' : "ORCAMENTO #{@report['numero']}"} - #{customer}.pdf".squeeze(' ')
  end

  def render
    @pdf = Prawn::Document.new(page_size: 'A4', margin: MARGIN, info: { Title: clean(filename.delete_suffix('.pdf')), Creator: 'Chat' })
    @pdf.font('Helvetica', size: FONT_SIZE)
    header
    customer
    lines
    closing
    observations
    signature
    watermark if @report['previa']
    page_numbers
    @pdf.render
  end

  private

  def width = @pdf.bounds.width

  def header
    emitter = @report['emitente'].to_h
    top = @pdf.cursor
    @pdf.bounding_box([0, top], width: width, height: 92) do
      @pdf.stroke_bounds
      logo(emitter['logo'])
      @pdf.bounding_box([96, 86], width: width - 270, height: 82) { emitter_lines(emitter) }
      @pdf.text_box(clean(title), at: [width - 170, 84], width: 162, align: :right, size: 12, style: :bold)
      @pdf.text_box(clean("Data: #{date(@report['data'])}"), at: [width - 170, 18], width: 162, align: :right, size: 9, style: :bold)
    end
  end

  def title = @report['previa'] ? 'Prévia do orçamento' : "Orçamento Nº #{@report['numero']}"

  def logo(bytes)
    return if bytes.blank?

    @pdf.image(StringIO.new(bytes), at: [6, 86], fit: [84, 80])
  rescue Prawn::Errors::UnsupportedImageType, StandardError
    nil
  end

  def emitter_lines(emitter)
    @pdf.font('Times-Roman', size: 9) { emitter_rows(emitter).each { |row| @pdf.text(clean(row), leading: 0.5) } }
  end

  def customer
    data = @report['cliente'].to_h
    @pdf.bounding_box([0, @pdf.cursor], width: width) do
      @pdf.move_down 4
      @pdf.indent(4, 4) do
        @pdf.text(clean("Cliente: #{[data['codigo'], data['nome']].compact_blank.join(' - ')}"), size: 9.5, style: :bold)
        @pdf.move_down 4
        customer_details(data)
      end
      @pdf.move_down 3
      @pdf.stroke_bounds
    end
    @pdf.move_down 12
  end

  def customer_details(data)
    # a coluna da direita flutua (não empurra o cursor): a caixa do cliente é elástica e mudaria a referência
    @pdf.float do
      @pdf.bounding_box([@pdf.bounds.width - 190, @pdf.cursor - 9], width: 190) { customer_right(data).each { |row| @pdf.text(clean(row)) } }
    end
    @pdf.bounding_box([0, @pdf.cursor], width: @pdf.bounds.width - 200) { customer_left(data).each { |row| @pdf.text(clean(row.to_s)) } }
  end

  def lines
    widths = column_widths
    row(LINE_COLUMNS.map(&:first), widths, bold: true, size: 8.5)
    @pdf.move_down 2
    @report['itens'].each_with_index do |item, index|
      dashed_line if index.positive?
      row(line_cells(item), widths)
    end
    @pdf.move_down 4
    @pdf.stroke_horizontal_rule
    @pdf.move_down 6
  end

  def column_widths
    fixed = LINE_COLUMNS.sum { |_, column_width, _| column_width.to_i }
    LINE_COLUMNS.map { |_, column_width, _| column_width || (width - fixed) }
  end

  def line_cells(item)
    [item['codigo'].to_s, item['descricao'], item['unidade'], qty(item['quantidade']), item['ncm'], item['cst'],
     item['icms'] && money(item['icms']), item['vr_icms'] && money(item['vr_icms']), money(item['desconto']),
     money(item['unitario']), money(item['total'])]
  end

  def row(cells, widths, bold: false, size: FONT_SIZE)
    @pdf.start_new_page if @pdf.cursor < 40
    top = @pdf.cursor
    heights = cells.each_with_index.map do |cell, index|
      box = Prawn::Text::Box.new(clean(cell.to_s), document: @pdf, at: [x_of(widths, index) + 2, top], width: widths[index] - 4,
                                                   align: LINE_COLUMNS[index][2], size: size, style: bold ? :bold : :normal)
      box.render
      box.height
    end
    @pdf.move_cursor_to(top - heights.max - 3)
  end

  def x_of(widths, index) = widths.first(index).sum

  def dashed_line
    @pdf.dash(2, space: 2)
    @pdf.stroke_horizontal_rule
    @pdf.undash
    @pdf.move_down 3
  end

  # condições de pagamento e Demais Condições à esquerda, totais à direita
  def closing
    @pdf.start_new_page if @pdf.cursor < 190
    top = @pdf.cursor
    @pdf.bounding_box([0, top], width: width - 210) { payment_and_conditions }
    left_bottom = @pdf.cursor
    @pdf.bounding_box([width - 200, top], width: 200) { totals }
    @pdf.move_cursor_to([left_bottom, @pdf.cursor].min - 6)
    @pdf.stroke_horizontal_rule
    @pdf.move_down 6
  end

  def payment_and_conditions
    @pdf.text('Condições de Pagamento:', size: 9, style: :bold)
    @pdf.text(clean(@report['pagamento'].presence || '-'))
    @pdf.move_down 3
    @pdf.text('Demais Condições:', size: 9, style: :bold)
    @pdf.move_down 2
    rows = @report['condicoes'].map { |name, value| "#{name}: #{value}" }
    @pdf.bounding_box([0, @pdf.cursor], width: @pdf.bounds.width) do
      @pdf.move_down 3
      @pdf.indent(3, 3) { rows.each { |text| @pdf.text(clean(text), size: 8.5) } }
      @pdf.move_down 3
      @pdf.stroke_bounds
    end
  end

  def totals
    rows = @report['totais'].reject { |name, value| value.to_f.zero? && %w[Desconto Acréscimo].include?(name) }
    rows += [['Valor Total do Orçamento', @report['total']]]
    rows.each do |name, value|
      @pdf.text_box(clean("#{name}:"), at: [0, @pdf.cursor], width: 140, align: :right, size: 8.5, style: :bold)
      @pdf.text_box(money(value), at: [140, @pdf.cursor], width: 58, align: :right, size: 8.5, style: :bold)
      @pdf.move_down 11
    end
  end

  def observations
    @pdf.text('Observações:', size: 9, style: :bold)
    @pdf.text(clean(@report['observacoes'].to_s.strip.presence || '-'))
  end

  def signature
    @pdf.start_new_page if @pdf.cursor < 70
    @pdf.move_down 36
    @pdf.stroke_line([width - 220, @pdf.cursor], [width - 10, @pdf.cursor])
    @pdf.move_down 3
    @pdf.text_box(clean(@report['vendedor'].to_s.upcase), at: [width - 220, @pdf.cursor], width: 210, align: :center, size: 8.5)
  end

  def watermark
    @pdf.repeat(:all) do
      @pdf.transparent(0.12) do
        @pdf.text_box('PRÉVIA - NÃO GRAVADO NO ERP'.encode('Windows-1252').encode('UTF-8'), at: [20, 470], width: width - 40, size: 34,
                                                                                            style: :bold, align: :center, rotate: 30)
      end
    end
  end

  def page_numbers
    return if @pdf.page_count < 2

    @pdf.number_pages('<page>/<total>', at: [width - 40, -6], width: 40, align: :right, size: 7)
  end
end
