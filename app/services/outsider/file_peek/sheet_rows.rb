# OUTSIDER: as primeiras linhas da primeira aba de um .xlsx para a miniatura (Outsider::FilePeek), sem ler a planilha
# inteira: só as primeiras linhas do XML e só os textos compartilhados que elas usam.
class Outsider::FilePeek::SheetRows
  ROWS = 8
  COLS = 6
  ROW = %r{<(?:\w+:)?row\b[^>]*(?<!/)>(.*?)</(?:\w+:)?row>}m
  CELL = %r{<(?:\w+:)?c\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?c>)}m
  SHARED = %r{<(?:\w+:)?si\b[^>]*>(.*?)</(?:\w+:)?si>}m
  TEXT = %r{<(?:\w+:)?t\b[^>]*>(.*?)</}m
  VALUE = %r{<(?:\w+:)?v>(.*?)</}m
  NUMBER = /\A-?\d+(\.\d+)?(E-?\d+)?\z/i

  def initialize(zip)
    @zip = zip
  end

  # { rows:, sheet: } ou nil
  def read
    path, name = first_sheet
    xml = @zip.text(path || 'xl/worksheets/sheet1.xml')
    return nil unless xml

    rows = texts(xml.enum_for(:scan, ROW).first(ROWS).map { |(row)| row_cells(row) })
    rows.any? ? { rows: rows, sheet: name }.compact : nil
  end

  private

  def first_sheet
    tag = @zip.text('xl/workbook.xml').to_s[/<(?:\w+:)?sheet\b[^>]*>/]
    return [nil, nil] unless tag

    [sheet_path(tag[/:id="([^"]*)"/, 1]), CGI.unescapeHTML(tag[/\bname="([^"]*)"/, 1].to_s).presence]
  end

  def sheet_path(rel_id)
    relation = @zip.text('xl/_rels/workbook.xml.rels').to_s.scan(/<Relationship\b[^>]*>/).find { |item| item.include?(%(Id="#{rel_id}")) }
    target = relation.to_s[/Target="([^"]*)"/, 1]
    return nil if target.blank?

    target.start_with?('/') ? target.delete_prefix('/') : "xl/#{target}"
  end

  def row_cells(row)
    cells = Array.new(COLS)
    row.scan(CELL).each do |attributes, inner|
      column = column_index(attributes[/\br="([A-Z]+)\d+"/, 1])
      cells[column] = cell(attributes[/\bt="([^"]*)"/, 1], inner.to_s) if column && column < COLS
    end
    cells
  end

  def cell(type, inner)
    return { s: inner[VALUE, 1].to_i } if type == 's'
    return { v: inner.scan(TEXT).flatten.join, type: 'str' } if type == 'inlineStr'

    { v: inner[VALUE, 1], type: type }
  end

  def column_index(letters)
    return nil if letters.blank?

    letters.each_char.reduce(0) { |sum, char| (sum * 26) + (char.ord - 64) } - 1
  end

  # textos das células, sem as colunas vazias do fim nem as linhas vazias
  def texts(cells)
    strings = shared_strings(cells.flatten.compact.pluck(:s).compact.max)
    rows = cells.map { |row| row.map { |cell| cell_text(cell, strings) } }
    width = rows.map { |row| used_width(row) }.max.to_i
    rows.map { |row| row.first(width) }.reject { |row| row.all?(&:blank?) }
  end

  def used_width(row)
    last = row.rindex(&:present?)
    last ? last + 1 : 0
  end

  def shared_strings(max_index)
    return [] if max_index.nil?

    @zip.text('xl/sharedStrings.xml').to_s.enum_for(:scan, SHARED).first(max_index + 1).map do |(inner)|
      CGI.unescapeHTML(inner.scan(TEXT).flatten.join)
    end
  end

  def cell_text(cell, strings)
    return '' unless cell

    value = cell.key?(:s) ? strings[cell[:s]].to_s : CGI.unescapeHTML(cell[:v].to_s)
    return value == '1' ? 'VERDADEIRO' : 'FALSO' if cell[:type] == 'b'

    number?(cell, value) ? number(value) : value.squish.first(40)
  end

  def number?(cell, value)
    !cell.key?(:s) && [nil, 'n'].include?(cell[:type]) && value.match?(NUMBER)
  end

  def number(value)
    float = value.to_f
    float == float.round ? float.round.to_s : format('%.2f', float).tr('.', ',')
  end
end
