# OUTSIDER: texto do PDF da proposta: **negrito**, campos automáticos, caracteres que a fonte desenha e
# valores em reais. Parte do Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::Text
  private

  # Texto com **negrito** e campos automáticos, em parágrafos
  def rich(text, **)
    @pdf.text(markup(text), inline_format: true, **)
  end

  def markup(text)
    # **negrito** só quando colado no texto ("houver**" das propostas é marca de nota, não negrito)
    escape(@fields.apply(text)).gsub(/\*\*(\S(?:[^*\n]*\S)?)\*\*/, '<b>\\1</b>')
  end

  def escape(text)
    clean(text).gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  # Só o que a fonte Helvetica do PDF desenha (Windows-1252)
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
