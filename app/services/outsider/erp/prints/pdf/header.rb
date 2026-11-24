# OUTSIDER: bloco "Cabeçalho" do Outsider::Erp::Prints::Pdf: logo (o do ERP, um enviado no modelo ou nenhum), dados da
# empresa emitente, título e subtítulo (aceitam {marcadores}) e o acabamento: linha na cor principal, faixa colorida
# ou nada.
# rubocop:disable Metrics -- desenho do PDF: coordenadas e medidas ficam juntas para dar para acompanhar o layout
module Outsider::Erp::Prints::Pdf::Header
  LOGO_BOX = [130, 54].freeze

  private

  def block_header(block)
    logo = header_logo(block)
    block['style'] == 'band' ? band_header(block, logo) : plain_header(block, logo)
    header_title(block)
    return unless block['style'] == 'line'

    @pdf.move_down(5)
    @pdf.fill_color(color('primary'))
    @pdf.fill_rectangle([0, @pdf.cursor], width_of_page, 2)
    @pdf.fill_color(color('text'))
    @pdf.move_down(2)
  end

  def header_logo(block)
    bytes = case block['logo']
            when 'erp' then @values.dig('emitter', 'logo')
            when 'upload' then @images[block['image_id'].to_i]
            end
    image?(bytes) ? bytes : nil
  end

  # logo à esquerda e a empresa à direita
  def plain_header(block, logo)
    top = @pdf.cursor
    draw_logo(logo, 0, top) if logo
    height = company_lines(block, logo ? LOGO_BOX[0] + 12 : 0, top, color('text'), align: logo ? :right : :left)
    @pdf.move_cursor_to(top - [logo ? LOGO_BOX[1] : 0, height].max)
  end

  # faixa na cor principal com o logo numa caixa branca e a empresa em letra clara
  def band_header(block, logo)
    top = @pdf.cursor
    height = 74
    @pdf.fill_color(color('primary'))
    @pdf.fill_rounded_rectangle([0, top], width_of_page, height, 6)
    if logo
      @pdf.fill_color('FFFFFF')
      @pdf.fill_rounded_rectangle([10, top - 10], LOGO_BOX[0] + 8, LOGO_BOX[1], 4)
      draw_logo(logo, 14, top - 12, [LOGO_BOX[0], LOGO_BOX[1] - 4], center: true)
    end
    @pdf.fill_color(color('text'))
    company_lines(block, logo ? LOGO_BOX[0] + 30 : 14, top - 10, contrast('primary'), align: :right, right_pad: 14)
    @pdf.move_cursor_to(top - height)
  end

  # logo dentro da caixa, mantendo a proporção; center: no meio da caixa (faixa), senão no canto de cima à esquerda
  def draw_logo(bytes, left, top, box = LOGO_BOX, center: false)
    ratio_w, ratio_h = image_size(bytes)
    scale = [box[0] / ratio_w, box[1] / ratio_h].min
    width = ratio_w * scale
    height = ratio_h * scale
    left += (box[0] - width) / 2 if center
    top -= (box[1] - height) / 2 if center
    @pdf.image(StringIO.new(bytes), at: [left, top], width: width, height: height)
  rescue Prawn::Errors::UnsupportedImageType, StandardError
    nil
  end

  # nome da empresa em negrito e as linhas de contato; devolve a altura usada
  def company_lines(block, left, top, text_color, align:, right_pad: 0)
    return 0 unless block['company']

    emitter = @values['emitter'].to_h
    lines = [["<b>#{esc(emitter['nome'])}</b>", base + 1]] + Array(emitter['lines']).map { |line| [esc(line), base - 1] }
    width = width_of_page - left - right_pad
    @pdf.bounding_box([left, top], width: width) do
      lines.each { |line, size| @pdf.text(line, size: size, inline_format: true, color: text_color, align: align, leading: 1) }
    end
    top - @pdf.cursor
  end

  # título grande na cor principal e o subtítulo num selo à direita
  def header_title(block)
    title = clean(fill(block['title'])).strip
    subtitle = clean(fill(block['subtitle'])).strip
    return if title.blank? && subtitle.blank?

    @pdf.move_down(12)
    top = @pdf.cursor
    badge = subtitle.present? ? subtitle_badge(subtitle, top) : 0
    @pdf.font(heading_font, style: :bold) do
      box(title, color('primary'), at: [0, top], width: width_of_page - badge - 8, size: base + 7, overflow: :shrink_to_fit,
                                   height: base + 12)
    end
    @pdf.move_cursor_to(top - (base + 12))
  end

  # selo arredondado na cor principal; devolve a largura
  def subtitle_badge(text, top)
    size = base - 1
    width = 0
    @pdf.font(heading_font, style: :bold) { width = @pdf.width_of(text, size: size) + 18 }
    width = [width, width_of_page / 2].min
    left = width_of_page - width
    @pdf.fill_color(color('primary'))
    @pdf.fill_rounded_rectangle([left, top - 1], width, size + 9, (size + 9) / 2.0)
    @pdf.font(heading_font, style: :bold) do
      box(text, contrast('primary'), at: [left, top - 5], width: width, align: :center, size: size, overflow: :shrink_to_fit,
                                     height: size + 3)
    end
    @pdf.fill_color(color('text'))
    width
  end
end
# rubocop:enable Metrics
