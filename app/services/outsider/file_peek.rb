# OUTSIDER: o começo de um documento da conversa, para a miniatura do cartão (estilo WhatsApp). Nada é gravado: o
# resultado fica só no cache por 30 dias (pela assinatura do arquivo).
#   PDF: o endereço temporário do arquivo; a tela desenha a primeira página (pdf.js) e conta as páginas.
#   Word, Excel e PowerPoint: a miniatura que o próprio Office guarda dentro do arquivo (docProps/thumbnail), quando
#     tem; senão o começo do texto (Word), as primeiras linhas da primeira aba (Excel) ou o texto do 1º slide.
#   CSV e texto: as primeiras linhas.
# type: pdf | image | text | table | none; pages quando o arquivo diz (Word: páginas; PowerPoint: slides).
class Outsider::FilePeek
  MAX_FILE = 25.megabytes
  PDF_MAX = 20.megabytes
  MAX_THUMB = 300.kilobytes
  LINES = 14
  ROWS = 8
  COLS = 6
  WORD = %w[docx docm dotx dotm].freeze
  EXCEL = %w[xlsx xlsm].freeze
  POWERPOINT = %w[pptx pptm ppsx potx].freeze
  TABLES = %w[csv tsv].freeze
  NONE = { type: 'none' }.freeze

  def initialize(attachment)
    @attachment = attachment
    @view = Outsider::FileView.new(attachment)
  end

  def payload
    return NONE unless @attachment.file.attached?

    extension = @view.extension
    return pdf if extension == 'pdf'
    return NONE if @view.size > MAX_FILE || !peekable?(extension)

    Rails.cache.fetch("outsider_peek:v1:#{@attachment.file.blob.checksum}:#{extension}", expires_in: 30.days) { build(extension) }
  rescue StandardError => e
    Rails.logger.warn("[outsider_file_peek] #{@attachment.id}: #{e.class} #{e.message.first(120)}")
    NONE
  end

  private

  def peekable?(extension)
    (WORD + EXCEL + POWERPOINT).include?(extension) || Outsider::FileView::TEXT.include?(extension)
  end

  def pdf
    @view.size > PDF_MAX ? NONE : { type: 'pdf', url: @view.signed_path }
  end

  def build(extension)
    data = @attachment.file.blob.open(&:read)
    return office(data, :word) if WORD.include?(extension)
    return office(data, :excel) if EXCEL.include?(extension)
    return office(data, :slides) if POWERPOINT.include?(extension)

    TABLES.include?(extension) ? csv(data, extension) : text(data)
  end

  def office(data, family)
    zip = Outsider::ZipEntries.new(data)
    result = thumbnail(zip) || office_content(zip, family) || NONE
    result.merge(pages: pages(zip, family)).compact
  end

  def office_content(zip, family)
    case family
    when :word then text_result(Outsider::FilePeek::WordText.new(zip.text('word/document.xml')).lines)
    when :excel then Outsider::FilePeek::SheetRows.new(zip).read&.merge(type: 'table')
    else text_result(slide_lines(zip.text('ppt/slides/slide1.xml')))
    end
  end

  def text_result(lines)
    lines.any? ? { type: 'text', lines: lines } : nil
  end

  def thumbnail(zip)
    name = zip.names.find { |entry| entry.match?(%r{\AdocProps/thumbnail\.(jpe?g|png)\z}i) }
    bytes = name && zip.read(name)
    return nil if bytes.blank? || bytes.bytesize > MAX_THUMB

    type = name.downcase.end_with?('png') ? 'image/png' : 'image/jpeg'
    { type: 'image', src: "data:#{type};base64,#{Base64.strict_encode64(bytes)}" }
  end

  def pages(zip, family)
    return zip.names.count { |name| name.match?(%r{\Appt/slides/slide\d+\.xml\z}) }.nonzero? if family == :slides
    return nil unless family == :word

    value = zip.text('docProps/app.xml').to_s[%r{<(?:\w+:)?Pages>(\d+)</}, 1]
    value.to_i.positive? ? value.to_i : nil
  end

  def slide_lines(xml)
    return [] unless xml

    lines = Nokogiri::XML(xml).xpath("//*[local-name()='p']").filter_map do |paragraph|
      paragraph.xpath(".//*[local-name()='t']").map(&:text).join.squish.presence&.first(160)
    end
    lines.first(LINES).each_with_index.map { |line, index| { t: line, h: index.zero? } }
  end

  def csv(data, extension)
    lines = readable(data).lines.first(ROWS)
    separator = extension == 'tsv' ? "\t" : guess_separator(lines.first.to_s)
    rows = lines.map { |line| csv_row(line.chomp, separator) }
    rows.any? ? { type: 'table', rows: rows } : NONE
  end

  def guess_separator(line)
    line.count(';') > line.count(',') ? ';' : ','
  end

  def csv_row(line, separator)
    values = begin
      CSV.parse_line(line, col_sep: separator).to_a
    rescue CSV::MalformedCSVError
      line.split(separator)
    end
    values.first(COLS).map { |value| value.to_s.squish.first(40) }
  end

  def text(data)
    lines = readable(data).lines.first(LINES).map { |line| { t: line.chomp.first(200) } }
    lines.any? { |line| line[:t].present? } ? { type: 'text', lines: lines, mono: true } : NONE
  end

  def readable(data)
    sample = data.to_s.byteslice(0, 64.kilobytes).dup.force_encoding('UTF-8')
    sample = sample.encode('UTF-8', 'ISO-8859-1') unless sample.valid_encoding?
    sample.scrub('').delete_prefix("\uFEFF")
  end
end
