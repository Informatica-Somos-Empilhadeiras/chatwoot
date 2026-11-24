# OUTSIDER: blocos de dados do Outsider::Erp::Prints::Pdf: grupo de campos (caixas, rótulo em cima ou "Rótulo: valor"),
# tabela (produtos, itens, check-in...), texto longo (avaliação, observações), totais do orçamento e assinaturas. Os
# campos e as colunas saem na ordem e com o liga/desliga do content['fields'] do modelo.
# rubocop:disable Metrics -- desenho do PDF: coordenadas e medidas ficam juntas para dar para acompanhar o layout
module Outsider::Erp::Prints::Pdf::Data
  # parágrafo maior que isso é partido (uma célula de tabela não pode passar de uma página)
  CHUNK = 900

  private

  # [chave, rótulo] dos campos ligados de uma lista, na ordem do modelo
  def chosen(list)
    Array(@content.dig('fields', list)).select { |item| item['on'] }.map do |item|
      [item['key'], Outsider::Erp::Prints::Catalog.label(@values['kind'], list, item['key'])]
    end
  end

  def block_fields(block)
    data = @values.dig('groups', block['group']).to_h
    pairs = chosen(block['group']).map { |key, label| [label, data[key].to_s] }
    pairs = pairs.select { |_, value| value.present? } if block['hide_empty']
    return if pairs.empty?

    section_title(block['title'])
    columns = block['columns'].to_i.clamp(1, 4)
    rows = pairs.each_slice(columns).map { |slice| slice.map { |pair| field_cell(pair, block['style']) } + Array.new(columns - slice.size, '') }
    boxed = block['style'] == 'boxes'
    @pdf.table(rows, width: width_of_page, column_widths: Array.new(columns, width_of_page / columns.to_f),
                     cell_style: { inline_format: true, size: base, padding: boxed ? [4, 6, 5, 6] : [2, 8, 4, 0],
                                   border_width: boxed ? 0.6 : 0, border_color: color('line'), text_color: color('text') })
  end

  def field_cell((label, value), style)
    return "<b>#{esc(label)}:</b> #{esc(value)}" if style == 'inline'

    "<font size='#{base - 2}'><color rgb='#{color('muted')}'><b>#{esc(label.upcase)}</b></color></font>\n#{esc(value.presence || '-')}"
  end

  def block_table(block)
    columns = chosen(block['table'])
    rows = Array(@values.dig('tables', block['table']))
    return if columns.empty? || (rows.empty? && block['hide_empty'])

    section_title(block['title'])
    data_table(block['table'], columns, rows, striped: block['striped'])
  end

  def data_table(list, columns, rows, striped: true)
    aligns = Outsider::Erp::Prints::Catalog.tables(@values['kind'])[list].last.to_h { |key, _, _, align| [key, (align || 'left').to_sym] }
    header = columns.map { |_, label| "<b>#{esc(label)}</b>" }
    body = rows.map { |row| columns.map { |key, _| esc(row[key]) } }
    body = [[{ content: clean('Nenhum item'), colspan: columns.size }]] if body.empty?
    @pdf.table([header] + body, header: true, width: width_of_page,
                                cell_style: { inline_format: true, size: base - 0.5, padding: [4, 5, 4, 5], border_width: 0.5,
                                              border_color: color('line'), text_color: color('text') }) do |table|
      table.row(0).background_color = color('primary')
      table.row(0).text_color = contrast('primary')
      table.row(0).border_color = color('primary')
      (1...table.row_length).each { |index| table.row(index).background_color = color('row') if striped && index.even? }
      columns.each_with_index { |(key, _), index| table.column(index).style(align: aligns[key] || :left) }
    end
  end

  def block_long_text(block)
    text = @values.dig('texts', block['field']).to_s.gsub("\r\n", "\n").strip
    return if text.blank? && block['hide_empty']

    section_title(block['title'])
    paragraphs = text.split(/\n{1,}/).flat_map { |part| chunks(part) }.presence || ['-']
    rows = paragraphs.map { |part| [esc(part)] }
    boxed = block['boxed']
    @pdf.table(rows, width: width_of_page,
                     cell_style: { inline_format: true, size: base, border_width: 0, leading: 2, text_color: color('text'),
                                   background_color: boxed ? color('box') : 'FFFFFF', padding: boxed ? [3, 10, 3, 10] : [1, 0, 1, 0] }) do |table|
      table.row(0).padding_top = boxed ? 8 : 1
      table.row(-1).padding_bottom = boxed ? 8 : 1
    end
  end

  def chunks(text)
    return [text] if text.length <= CHUNK

    text.scan(/.{1,#{CHUNK}}(?:[.;,!?]\s|\s|\z)/mo).map(&:strip).compact_blank
  end

  # totais do orçamento: rótulo à esquerda e valor à direita; o Total por último, destacado
  def block_totals(block)
    data = @values.dig('groups', 'totais').to_h
    pairs = chosen('totais').map { |key, label| [key, label, data[key].to_s] }
    pairs = pairs.select { |key, _, value| value.present? || key == 'total' } if block['hide_zero']
    return if pairs.empty?

    section_title(block['title'])
    width = block['width'] == 'full' ? width_of_page : width_of_page * 0.45
    rows = pairs.map { |_, label, value| [esc(label), esc(value.presence || '-')] }
    last = pairs.last.first == 'total'
    @pdf.indent(width_of_page - width) do
      @pdf.table(rows, width: width, column_widths: [width * 0.55, width * 0.45],
                       cell_style: { inline_format: true, size: base, padding: [4, 8, 4, 8], borders: [:bottom], border_width: 0.5,
                                     border_color: color('line'), text_color: color('text') }) do |table|
        table.column(1).align = :right
        if last
          table.row(-1).background_color = color('box')
          table.row(-1).font_style = :bold
          table.row(-1).text_color = color('primary')
          table.row(-1).size = base + 2
        end
      end
    end
  end

  # linhas de assinatura lado a lado (até 4), com o nome de quem assina quando o relatório sabe
  def block_signatures(block)
    labels = Array(block['lines']).first(4)
    return if labels.empty?

    height = 64 + (block['date'] ? 14 : 0)
    need(height)
    gap = 18
    width = (width_of_page - (gap * (labels.size - 1))) / labels.size
    top = @pdf.cursor
    labels.each_with_index { |label, index| signature(label, block, index * (width + gap), top, width) }
    @pdf.move_cursor_to(top - height)
  end

  def signature(label, block, left, top, width)
    line_y = top - 38
    name = block['names'] ? clean(person_for(label)).strip : ''
    if name.present?
      @pdf.text_box(name, at: [left, line_y + 13], width: width, align: :center, size: base - 1, height: base + 2,
                          overflow: :shrink_to_fit)
    end
    @pdf.stroke_color(color('text'))
    @pdf.line_width(0.6)
    @pdf.stroke_line([left, line_y], [left + width, line_y])
    box(clean(label), color('muted'), at: [left, line_y - 4], width: width, align: :center, size: base - 1)
    return unless block['date']

    box(clean('Data: ____/____/______'), color('muted'), at: [left, line_y - 18], width: width, align: :center, size: base - 2)
  end
end
# rubocop:enable Metrics
