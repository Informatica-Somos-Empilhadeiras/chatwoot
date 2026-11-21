# OUTSIDER: os textos do PDF do orçamento (Outsider::Erp::QuotePdf) e do relatório da OS (Outsider::Erp::ServiceOrderPdf):
# logo e linhas do emitente do cabeçalho, linhas do cliente, CNPJ/CPF, datas, valores no formato brasileiro e a limpeza
# para Windows-1252 (as fontes do próprio PDF não têm o resto).
module Outsider::Erp::QuotePdfText
  private

  def logo(bytes)
    return if bytes.blank?

    @pdf.image(StringIO.new(bytes), at: [6, 86], fit: [84, 80])
  rescue Prawn::Errors::UnsupportedImageType, StandardError
    nil
  end

  def emitter_lines(emitter)
    @pdf.font('Times-Roman', size: 9) { emitter_rows(emitter).each { |row| @pdf.text(clean(row), leading: 0.5) } }
  end

  def emitter_rows(emitter)
    address = [[emitter['endereco'], emitter['numero']].compact_blank.join(', '), emitter['bairro'],
               [emitter['cidade'], emitter['uf']].compact_blank.join('-')].compact_blank.join(' - ')
    [emitter['nome'], pair(label('CNPJ', document(emitter['cnpj'])), label('I.E.', emitter['ie'])), address,
     label('Fone', emitter['fone']), label('Home Page', emitter['site']), label('E-mail', emitter['email'])].compact_blank
  end

  def customer_left(data)
    address = [[data['endereco'], data['numero']].compact_blank.join(', '), data['complemento'], data['bairro']].compact_blank.join(' - ')
    city = label('Cidade', [data['cidade'], data['uf']].compact_blank.join(' - '))
    [pair(label('CNPJ', document(data['documento'])), label('Insc. Est.', data['ie'])), label('Endereço', address),
     pair(city, label('Cep', data['cep']), gap: '   ')]
  end

  def customer_right(data)
    ["Contato: #{data['contato']}", "Fone: #{[data['fone_contato'], data['fone'], data['celular']].compact_blank.first}"]
  end

  def pair(first, second, gap: '     ') = [first, second].compact.join(gap)

  def label(name, value) = value.present? ? "#{name}: #{value}" : nil

  # 52346349000183 -> 52.346.349/0001-83 (CPF com 11 dígitos também); outro formato fica como veio
  def document(value)
    digits = value.to_s.gsub(/\D/, '')
    return digits.sub(/\A(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})\z/, '\1.\2.\3/\4-\5') if digits.length == 14
    return digits.sub(/\A(\d{3})(\d{3})(\d{3})(\d{2})\z/, '\1.\2.\3-\4') if digits.length == 11

    value.to_s.strip.presence
  end

  def date(value)
    Date.parse(value.to_s).strftime('%d/%m/%Y')
  rescue ArgumentError, TypeError
    ''
  end

  def money(value)
    ActiveSupport::NumberHelper.number_to_rounded(value.to_f, precision: 2, separator: ',', delimiter: '.')
  end

  def qty(value)
    number = value.to_f
    number == number.round ? number.round.to_s : ActiveSupport::NumberHelper.number_to_rounded(number, precision: 2, separator: ',')
  end

  def clean(text)
    text.to_s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '').encode('UTF-8')
  end
end
