# OUTSIDER: desenha um modelo de relatório do estúdio (content de Outsider::Erp::PrintTemplate, já limpo) com os valores
# de uma OS ou de um orçamento (Outsider::Erp::Prints::Values) num PDF A4. Os blocos saem um embaixo do outro, na
# ordem do modelo, com as cores, fontes e tamanho da identidade visual; tabelas e checklist quebram página sozinhos.
# As fontes são as do próprio PDF (Helvetica, Times, Courier), então o texto sai em Windows-1252.
# Imagens: logo do ERP (values), imagens enviadas no modelo (images: id => bytes) e fotos do checklist (bytes ou amostra).
# rubocop:disable Metrics -- desenho do PDF: coordenadas e medidas ficam juntas para dar para acompanhar o layout
class Outsider::Erp::Prints::Pdf
  include Outsider::Erp::QuotePdfText
  include Outsider::Erp::Prints::Pdf::Helpers
  include Outsider::Erp::Prints::Pdf::Header
  include Outsider::Erp::Prints::Pdf::Data
  include Outsider::Erp::Prints::Pdf::Checklist

  MARGINS = { 's' => 24, 'm' => 36, 'l' => 50 }.freeze
  FONTS = { 'helvetica' => 'Helvetica', 'times' => 'Times-Roman', 'courier' => 'Courier' }.freeze
  GAP = 10

  Prawn::Fonts::AFM.hide_m17n_warning = true

  def initialize(content, values, images: {}, title: nil)
    @content = content.to_h
    @theme = Outsider::Erp::Prints::Content.normalize_theme(@content['theme'])
    @values = values.to_h
    @images = images.to_h
    @title = title
  end

  def render
    margin = MARGINS.fetch(@theme['margin'], 36)
    @pdf = Prawn::Document.new(page_size: 'A4', margin: [margin, margin, margin + 10, margin],
                               info: { Title: clean(@title.to_s), Creator: 'Chat' })
    @pdf.font(body_font, size: base)
    @pdf.fill_color(color('text'))
    Array(@content['blocks']).each_with_index { |block, index| draw(block, index) }
    page_numbers if @theme['page_numbers']
    preview_mark if @values['preview']
    @pdf.render
  end

  private

  def draw(block, index)
    method = "block_#{block['type']}"
    return unless respond_to?(method, true)

    @pdf.move_down(GAP) if index.positive? && %w[spacer page_break].exclude?(block['type']) && !page_top?
    send(method, block)
  rescue Prawn::Errors::CannotFit, Prawn::Errors::UnsupportedImageType => e
    Rails.logger.warn("[Prints::Pdf] bloco #{block['type']} não coube: #{e.message}")
  end

  # ---- blocos simples ----

  def block_heading(block)
    size = { 'lg' => base + 8, 'md' => base + 5, 'sm' => base + 2 }.fetch(block['size'], base + 5)
    @pdf.font(heading_font, style: :bold) do
      @pdf.text(clean(fill(block['text'])), size: size, color: color(block['color']), align: block['align'].to_sym, leading: 1)
    end
  end

  def block_text(block)
    text = clean(fill(block['text']))
    return if text.blank?

    size = { 'sm' => base - 1, 'md' => base, 'lg' => base + 2 }.fetch(block['size'], base)
    @pdf.text(text, size: size, color: color(block['color']), align: block['align'].to_sym, leading: 2)
  end

  def block_divider(block)
    @pdf.move_down(2)
    @pdf.stroke_color(color(block['color']))
    @pdf.line_width(block['thickness'].to_i.clamp(1, 4))
    @pdf.stroke_horizontal_rule
    @pdf.line_width(1)
    @pdf.move_down(2)
  end

  def block_spacer(block)
    height = block['height'].to_i.clamp(4, 200)
    return @pdf.start_new_page if height > @pdf.cursor

    @pdf.move_down(height)
  end

  def block_page_break(_block)
    @pdf.start_new_page unless page_top?
  end

  def block_image(block)
    bytes = @images[block['image_id'].to_i]
    return unless image?(bytes)

    width = width_of_page * block['width'].to_i.clamp(10, 100) / 100.0
    info = image_size(bytes)
    height = [width * info[1] / info[0].to_f, 320].min
    need(height)
    left = { 'left' => 0, 'right' => width_of_page - width }.fetch(block['align'], (width_of_page - width) / 2)
    @pdf.image(StringIO.new(bytes), at: [left, @pdf.cursor], fit: [width, height])
    @pdf.move_down(height)
  end

  # prévia do rascunho do orçamento (ainda não gravado no ERP): aviso no rodapé de todas as páginas
  def preview_mark
    @pdf.repeat(:all) do
      box(clean('PRÉVIA - orçamento ainda não gravado no ERP'), color('primary'), at: [0, -12], width: width_of_page / 2,
                                                                                  size: base - 2, style: :bold)
    end
  end

  def page_numbers
    @pdf.number_pages(clean('Página <page> de <total>'), at: [0, -12], width: width_of_page, align: :right, size: base - 2,
                                                         color: color('muted'))
  end
end
# rubocop:enable Metrics
