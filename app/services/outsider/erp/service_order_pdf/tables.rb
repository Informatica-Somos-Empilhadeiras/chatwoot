# OUTSIDER: as tabelas do relatório da OS (eventos de check-in/out e produtos/serviços), como no original: o título fica
# numa faixa de borda azul, o cabeçalho e as linhas em grade cinza, tudo com filetes de 0,84. Se a tabela não couber,
# segue na página seguinte repetindo o cabeçalho. Parte do Outsider::Erp::ServiceOrderPdf.
module Outsider::Erp::ServiceOrderPdf::Tables
  include Outsider::Erp::ServiceOrderPdf::Layout

  HEAD = { size: 8, style: :bold, align: :center }.freeze

  private

  def table(spec, rows)
    return if rows.empty?

    top = @y + (@after == :box ? 7.79 : 13.44)
    top = page_break(12.0) if top + 21.0 + 17.34 + 18.78 > BOTTOM
    caption_row(spec, top)
    y = head_row(spec, top + 21.0, under_caption: true)
    rows.each { |cells| y = body_row(spec, y, cells) }
    @y = y + BORDER
    @after = :table
  end

  def caption_row(spec, top)
    bar(LEFT, top, [RIGHT - LEFT, BORDER], BLUE)
    bar(LEFT, top, [BORDER, 21.84], BLUE)
    bar(spec[:borders].last, top, [BORDER, 21.84], BLUE)
    write_center(spec[:caption].upcase, top + 14.28)
  end

  # devolve o y da linha de baixo do cabeçalho (onde começa a 1ª linha de dados); em cima, azul sob o título
  def head_row(spec, top, under_caption:)
    spec[:borders].each { |left| bar(left, top, [BORDER, 17.34 + BORDER], GRID) }
    bar(LEFT, top, [RIGHT - LEFT, BORDER], under_caption ? BLUE : GRID)
    bar(LEFT, top + 17.34, [RIGHT - LEFT, BORDER], GRID)
    spec[:heads].each_with_index { |text, index| write_cell(spec, index, text, top + 12.06, HEAD) }
    top + 17.34
  end

  # uma linha de dados (cresce se algum texto quebrar); devolve o y da linha seguinte
  def body_row(spec, top, cells)
    lines = cells.each_with_index.map { |text, index| wrap(text, cell_width(spec, index), size: 9) }
    height = 18.78 + ((lines.map(&:size).max - 1) * 10.15)
    top = head_row(spec, page_break(12.0), under_caption: false) if top + height + BORDER > BOTTOM
    spec[:borders].each { |left| bar(left, top, [BORDER, height + BORDER], GRID) }
    bar(LEFT, top + height, [RIGHT - LEFT, BORDER], GRID)
    row_texts(spec, top, lines)
    top + height
  end

  def row_texts(spec, top, lines)
    lines.each_with_index do |cell, index|
      font = { size: 9, style: :normal, align: spec[:aligns][index] }
      cell.each_with_index { |line, row| write_cell(spec, index, line, top + 12.84 + (row * 10.15), font) }
    end
  end

  # font: { size:, style:, align: } — texto à esquerda com 3,66 de folga ou centralizado entre as bordas da coluna
  def write_cell(spec, index, text, baseline, font)
    left = spec[:borders][index] + BORDER
    right = spec[:borders][index + 1]
    text_width = width(text, size: font[:size], style: font[:style])
    x = font[:align] == :center ? ((left + right) / 2) - (text_width / 2) : left + 3.66
    write(text, [x, baseline], size: font[:size], style: font[:style])
  end

  def cell_width(spec, index) = spec[:borders][index + 1] - spec[:borders][index] - BORDER - 7.32
end
