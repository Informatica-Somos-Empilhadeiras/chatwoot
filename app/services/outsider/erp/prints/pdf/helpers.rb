# OUTSIDER: medidas, cores, fontes e textos comuns aos blocos do Outsider::Erp::Prints::Pdf.
module Outsider::Erp::Prints::Pdf::Helpers
  PLACEHOLDER = /\{([a-z_]+)\}/

  private

  def base = @theme['size'].to_i
  def body_font = Outsider::Erp::Prints::Pdf::FONTS.fetch(@theme['body_font'], 'Helvetica')
  def heading_font = Outsider::Erp::Prints::Pdf::FONTS.fetch(@theme['heading_font'], 'Helvetica')
  def width_of_page = @pdf.bounds.width

  # cor da identidade visual sem o # (o Prawn quer RRGGBB); nome desconhecido vira a cor do texto
  def color(name)
    hex = @theme['colors'][name.to_s] || @theme['colors']['text']
    hex.to_s.delete('#')
  end

  # cor de texto legível sobre um fundo (branco ou o texto escuro)
  def contrast(name)
    hex = color(name)
    red, green, blue = hex.scan(/../).map { |pair| pair.to_i(16) }
    ((red * 299) + (green * 587) + (blue * 114)) / 1000 > 150 ? color('text') : 'FFFFFF'
  end

  # troca {numero}, {cliente}... pelos valores; marcador desconhecido fica como está
  def fill(text)
    marks = @values['placeholders'].to_h
    text.to_s.gsub(PLACEHOLDER) { marks.key?(Regexp.last_match(1)) ? marks[Regexp.last_match(1)].to_s : Regexp.last_match(0) }
  end

  def page_top? = @pdf.cursor >= @pdf.bounds.height - 0.5

  # caixa de texto com cor (o text_box do Prawn não aceita :color): a cor e o estilo vão no próprio trecho
  def box(text, hex, **options)
    style = options.delete(:style)
    @pdf.formatted_text_box([{ text: text.to_s, color: hex, styles: style ? [style] : nil }.compact], options)
  end

  # começa outra página se o que vem não couber no que sobrou desta
  def need(height)
    @pdf.start_new_page if height > @pdf.cursor && !page_top?
  end

  # texto para o inline_format do Prawn (escapa < > &), já em Windows-1252
  def esc(text) = clean(text).gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')

  def image?(bytes) = bytes.is_a?(String) && bytes.b.start_with?("\xFF\xD8".b, "\x89PNG".b)

  # largura e altura da imagem (só para a proporção); na dúvida, 4:3
  def image_size(bytes)
    info = Prawn.image_handler.find(bytes).new(bytes)
    [info.width.to_f.nonzero? || 4.0, info.height.to_f.nonzero? || 3.0]
  rescue StandardError
    [4.0, 3.0]
  end

  # título de seção: texto em maiúsculas na cor principal e um traço curto na cor de destaque embaixo
  def section_title(text)
    text = clean(fill(text)).strip
    return if text.blank?

    need(base * 4)
    @pdf.font(heading_font, style: :bold) do
      @pdf.text(text.upcase, size: base + 1, color: color('primary'), character_spacing: 0.4)
    end
    @pdf.move_down(2)
    @pdf.fill_color(color('accent'))
    @pdf.fill_rectangle([0, @pdf.cursor], 28, 2)
    @pdf.fill_color(color('text'))
    @pdf.move_down(7)
  end

  # nome de quem assina pelo rótulo da linha (Técnico, Cliente, Vendedor, Responsável)
  def person_for(label)
    people = @values['people'].to_h
    text = I18n.transliterate(label.to_s).downcase
    return people['tecnico'] if text.include?('tecn')
    return people['cliente'] if text.include?('client')
    return people['vendedor'] if text.include?('vend')

    people['tecnico'].presence || people['vendedor'] if text.include?('respons')
  end
end
