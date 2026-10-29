# OUTSIDER: números de telefone da central (Entrega 22). A operadora e o vendedor mandam o número de jeitos
# diferentes ("062 99999-8888", "5562999998888", "+55 62 ..."); aqui vira o número nacional (DDD + número)
# para discar e comparar, e o formato do Chatwoot (+55...) para gravar e achar o contato.
module Outsider::Voice::PhoneNumber
  # 0800, 0300 (11 dígitos) e 4003/4004/4020 (8 dígitos) são liberados; 0900 (pago) e internacional não
  SPECIAL = /\A(0800|0300)\d{7}\z|\A40(03|04|20)\d{4}\z/
  NATIONAL = /\A[1-9][1-9]\d{8,9}\z/

  module_function

  def digits(value)
    value.to_s.delete('^0-9')
  end

  # DDD + número (10 ou 11 dígitos), número especial liberado ou nil; "+" de outro país não passa
  def national(value)
    number = digits(value)
    return number if number.match?(SPECIAL)
    return if value.to_s.strip.start_with?('+') && !number.start_with?('55')

    # 55 ou 0 na frente de DDD + número
    number = number.sub(/\A(?:55|0)(?=\d{10,11}\z)/, '')
    number if number.match?(NATIONAL)
  end

  def e164(value)
    number = national(value)
    return if number.nil? || number.match?(SPECIAL)

    "+55#{number}"
  end

  # Número de outro país ("+1 415...", "001415..."), guardado com o "+" para o painel saber que é internacional
  # (Entrega 25); nil se for do Brasil ou não parecer internacional
  def foreign(value)
    text = value.to_s.strip
    number = digits(text)
    number = number.delete_prefix('00') if text.start_with?('00')
    return unless text.start_with?('+', '00') && number.length >= 7 && !number.start_with?('55')

    "+#{number}"
  end

  # Mesmo número com ou sem o 9 da frente: compara DDD e os 8 últimos dígitos
  def same?(first, second)
    a = national(first)
    b = national(second)
    a.present? && b.present? && a[0, 2] == b[0, 2] && a[-8..] == b[-8..]
  end

  # Contato da conta com esse número; o que falou por último primeiro
  def find_contact(account, value)
    number = national(value)
    return if number.nil? || number.match?(SPECIAL)

    account.contacts.where('phone_number LIKE ?', "%#{number[-8..]}").order(Arel.sql('last_activity_at DESC NULLS LAST'))
           .find { |contact| same?(contact.phone_number, number) }
  end
end
