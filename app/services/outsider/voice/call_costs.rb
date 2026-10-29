# OUTSIDER: custo de cada ligação (Entrega 25), com os preços de Telefonia > Configurações
# (Outsider::Voice::SettingsBilling). Só ligação atendida custa: o valor por ligação mais o valor por minuto
# vezes o tempo que a operadora cobra (mínimo de 30 s e depois de 6 em 6 s, por exemplo).
#
# Tipo da ligação feita: fixo ou celular (11 dígitos com 9), do mesmo DDD da linha que ligou ou de outro;
# internacional; 0800/0300/400X (special). Recebida é "inbound". Entre ramais não custa.
class Outsider::Voice::CallCosts
  Region = Outsider::Voice::Region

  def initialize(settings)
    @costs = settings.costs
  end

  def kind(call)
    return if call.internal?
    return 'inbound' if call.inbound?
    return 'special' if Region.special?(call.to_number)

    outbound_kind(call, Region.of(call.to_number))
  end

  # em reais, com 4 casas
  def cost(call)
    kind = kind(call)
    return 0.0 if kind.nil? || !call.answered? || call.talk_seconds.to_i <= 0

    rate = @costs['rates'][kind]
    (rate['call'] + (rate['minute'] * billed_seconds(call.talk_seconds) / 60.0)).round(4)
  end

  def outbound_kind(call, region)
    return 'long_fixed' if region.nil?
    return 'international' if region[:state] == Region::INTERNATIONAL

    local = region[:ddd] == Region.of(call.did.presence || call.from_number)&.dig(:ddd)
    "#{local ? 'local' : 'long'}_#{region[:mobile] ? 'mobile' : 'fixed'}"
  end

  def billed_seconds(seconds)
    case @costs['billing']
    when 'second' then seconds
    when 'minute' then (seconds / 60.0).ceil * 60
    else
      minimum = @costs['billing'] == '60_6' ? 60 : 30
      seconds <= minimum ? minimum : minimum + (((seconds - minimum) / 6.0).ceil * 6)
    end
  end
end
