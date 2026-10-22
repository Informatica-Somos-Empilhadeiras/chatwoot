# OUTSIDER: texto do PDF da proposta: **negrito**, ==destaque amarelo==, campos automáticos, o estilo do bloco
# (tamanho, negrito, destaque), caracteres que a fonte desenha e valores em reais. Parte do
# Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::Text
  # marca interna do ==destaque== entre a marcação e o desenho
  HIGHLIGHT_ANCHOR = '__outsider_highlight'.freeze

  # Pinta o fundo amarelo atrás do trecho (callback de texto do Prawn)
  class Highlight
    def initialize(pdf)
      @pdf = pdf
    end

    def render_behind(fragment)
      color = @pdf.fill_color
      @pdf.fill_color(Outsider::Crm::ProposalPdf::HIGHLIGHT)
      @pdf.fill_rectangle(fragment.top_left, fragment.width, fragment.height)
      @pdf.fill_color(color)
    end
  end

  private

  def with_block_style(settings, &)
    @style = { bold: settings['bold'], highlight: settings['highlight'], size: settings['size'] }
    @pdf.font_size(settings['size'], &)
  ensure
    @style = nil
  end

  def block_size
    @style&.dig(:size) || Outsider::Crm::ProposalPdf::FONT_SIZE
  end

  # Texto com **negrito**, ==destaque== e campos automáticos, em parágrafos
  def rich(text, **)
    write(fragments(markup(text)), **)
  end

  # Texto simples, sem marcação
  def say(text, **)
    write([{ text: clean(text) }], **)
  end

  def fragments(inline)
    Prawn::Text::Formatted::Parser.format(inline)
  end

  def write(list, bold: false, highlight: false, size: nil, **options)
    options[:size] = size if size
    @pdf.formatted_text(list.map { |fragment| styled(fragment, bold, highlight) }, options)
  end

  def styled(fragment, bold, highlight)
    fragment = fragment.dup
    fragment[:styles] = Array(fragment[:styles]) | [:bold] if bold || block_style?(:bold)
    fragment[:callback] = highlighter if fragment.delete(:anchor) == HIGHLIGHT_ANCHOR || highlight || block_style?(:highlight)
    fragment
  end

  def block_style?(key)
    @style&.dig(key)
  end

  def highlighter
    @highlighter ||= Highlight.new(@pdf)
  end

  # table: em quadro o Prawn não pinta trecho; o ==destaque== sai só sem as marcas
  def markup(text, table: false)
    # **negrito** só quando colado no texto ("houver**" das propostas é marca de nota, não negrito)
    html = escape(@fields.apply(text)).gsub(/\*\*(\S(?:[^*\n]*\S)?)\*\*/, '<b>\\1</b>')
    html.gsub(/==(\S(?:[^=\n]*\S)?)==/) { table ? Regexp.last_match(1) : "<link anchor=\"#{HIGHLIGHT_ANCHOR}\">#{Regexp.last_match(1)}</link>" }
  end

  def escape(text)
    clean(text).gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  # Só o que as fontes do PDF desenham (Windows-1252)
  def clean(text)
    text.to_s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '').encode('UTF-8')
  end

  def money(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0, unit: 'R$ ', separator: ',', delimiter: '.')
  end

  def quantity(value)
    ActiveSupport::NumberHelper.number_to_rounded(value.to_d, precision: 2, separator: ',', delimiter: '.')
  end
end
