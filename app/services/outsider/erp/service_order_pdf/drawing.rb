# OUTSIDER: o básico do desenho do relatório da OS: texto na linha de base exata (Helvetica, sem kerning, como saiu no
# original), centralizado ou alinhado pela direita, filetes e a quebra de linha. Parte do Outsider::Erp::ServiceOrderPdf.
module Outsider::Erp::ServiceOrderPdf::Drawing
  include Outsider::Erp::ServiceOrderPdf::Layout

  private

  # at: [x, linha de base contada do topo]
  def write(text, at, size: 10, style: :normal, color: TEXT)
    return if text.blank?

    @pdf.font('Helvetica', style: style) do
      @pdf.fill_color(color)
      @pdf.draw_text(clean(text), at: [at[0], PAGE_HEIGHT - at[1]], size: size)
    end
  end

  # títulos de seção e de tabela: negrito cinza no centro da página
  def write_center(text, baseline)
    write(text, [CENTER - (width(text, style: :bold) / 2), baseline], style: :bold, color: MUTED)
  end

  # partes com pesos diferentes alinhadas pela direita (ORDEM DE SERVIÇO: 850)
  def write_right(parts, baseline)
    left = RIGHT - 0.12 - parts.sum { |text, style| width(text, size: 9, style: style) }
    parts.each do |text, style|
      write(text, [left, baseline], size: 9, style: style)
      left += width(text, size: 9, style: style)
    end
  end

  # size: [largura, altura]
  def bar(left, top, size, color)
    @pdf.fill_color(color)
    @pdf.fill_rectangle([left, PAGE_HEIGHT - top], *size)
  end

  def width(text, size: 10, style: :normal)
    measured = nil
    @pdf.font('Helvetica', style: style) { measured = @pdf.width_of(clean(text), size: size) }
    measured
  end

  # quebra por palavra como o navegador; \n quebra a linha e linha vazia conta
  def wrap(text, limit, size: 10, style: :normal)
    text.to_s.split("\n", -1).flat_map { |paragraph| wrap_paragraph(paragraph, limit, size, style) }.presence || ['']
  end

  # os espaços ficam como o ERP mandou (o original mantém o espaço duplo de "050309FD657 -  CPD30...")
  def wrap_paragraph(paragraph, limit, size, style)
    paragraph.split(/ /, -1).each_with_object([nil]) do |word, lines|
      candidate = lines.last.nil? ? word : "#{lines.last} #{word}"
      fits = lines.last.nil? || word.empty? || width(candidate, size: size, style: style) <= limit
      fits ? lines[-1] = candidate : lines << word
    end.map(&:to_s)
  end
end
