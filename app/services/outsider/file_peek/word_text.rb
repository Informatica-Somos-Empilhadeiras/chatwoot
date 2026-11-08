# OUTSIDER: o começo de um .docx para a miniatura (Outsider::FilePeek): parágrafos na ordem, com o título marcado (estilo
# de título ou tudo em negrito), e as linhas de tabela com as células separadas.
class Outsider::FilePeek::WordText
  LINES = 14
  COLS = 6
  HEADING = /heading|t[ií]tulo|title/i

  def initialize(xml)
    @xml = xml
    @lines = []
  end

  # [{ t:, h: } | { r: [células] }]
  def lines
    body = Nokogiri::XML(@xml.to_s).at_xpath("//*[local-name()='body']")
    return [] unless body

    body.element_children.each do |node|
      break if @lines.size >= LINES

      read_node(node)
    end
    trimmed
  end

  private

  def read_node(node)
    case node.name
    when 'p' then paragraph(node)
    when 'tbl' then table(node)
    when 'sdt' then node.xpath(".//*[local-name()='p']").each { |item| paragraph(item) }
    end
  end

  # linha em branco só uma por vez, e nunca no começo
  def paragraph(node)
    content = text_of(node)
    return if content.blank? && @lines.last.to_h[:t].to_s.empty?

    @lines << { t: content.first(220), h: heading?(node, content) }
  end

  def table(node)
    node.xpath("*[local-name()='tr']").first(6).each do |row|
      cells = row.xpath("*[local-name()='tc']").first(COLS).map { |cell| text_of(cell).first(40) }
      @lines << { r: cells } if cells.any?(&:present?)
    end
  end

  def heading?(node, content)
    return false if content.blank?

    style = node.at_xpath(".//*[local-name()='pStyle']")&.attributes&.dig('val')&.value.to_s
    style.match?(HEADING) || node.xpath(".//*[local-name()='r'][.//*[local-name()='t']]").all? { |run| run.at_xpath(".//*[local-name()='b']") }
  end

  def text_of(node)
    node.xpath(".//*[local-name()='t']").map(&:text).join.squish
  end

  def trimmed
    list = @lines.first(LINES)
    list.pop while list.last && list.last[:t] == ''
    list
  end
end
