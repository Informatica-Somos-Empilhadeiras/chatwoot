# OUTSIDER: de onde é o número do cliente (Entrega 25), para o mapa e a lista por DDD do painel: o estado sai
# do DDD (a mesma tabela de app/javascript/dashboard/routes/dashboard/outsider/voice/brazil.js); número de
# outro país (+ que não é 55) vira INTERNATIONAL. Também diz se é celular (11 dígitos começando com 9).
module Outsider::Voice::Region
  INTERNATIONAL = 'INT'.freeze
  DDD_STATES = {
    'SP' => [11, 12, 13, 14, 15, 16, 17, 18, 19], 'RJ' => [21, 22, 24], 'ES' => [27, 28], 'MG' => [31, 32, 33, 34, 35, 37, 38],
    'PR' => [41, 42, 43, 44, 45, 46], 'SC' => [47, 48, 49], 'RS' => [51, 53, 54, 55], 'DF' => [61], 'GO' => [62, 64], 'TO' => [63],
    'MT' => [65, 66], 'MS' => [67], 'AC' => [68], 'RO' => [69], 'BA' => [71, 73, 74, 75, 77], 'SE' => [79], 'PE' => [81, 87],
    'AL' => [82], 'PB' => [83], 'RN' => [84], 'CE' => [85, 88], 'PI' => [86, 89], 'PA' => [91, 93, 94], 'AM' => [92, 97],
    'RR' => [95], 'AP' => [96], 'MA' => [98, 99]
  }.freeze
  BY_DDD = DDD_STATES.flat_map { |state, ddds| ddds.map { |ddd| [ddd.to_s, state] } }.to_h.freeze

  module_function

  # { ddd: '62', state: 'GO', mobile: true }, { ddd: nil, state: 'INT' } ou nil (sem número ou 0800)
  def of(number)
    value = number.to_s.strip
    return { ddd: nil, state: INTERNATIONAL, mobile: false } if international?(value)

    national = Outsider::Voice::PhoneNumber.national(value)
    return if national.nil? || national.match?(Outsider::Voice::PhoneNumber::SPECIAL)

    ddd = national[0, 2]
    { ddd: ddd, state: BY_DDD[ddd], mobile: national.length == 11 && national[2] == '9' }
  end

  def international?(value)
    value.start_with?('+') && !value.start_with?('+55')
  end

  def special?(number)
    Outsider::Voice::PhoneNumber.digits(number).match?(Outsider::Voice::PhoneNumber::SPECIAL)
  end
end
