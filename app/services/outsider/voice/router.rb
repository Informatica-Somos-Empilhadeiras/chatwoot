# OUTSIDER: decide o caminho de cada ligação quando a central pergunta (Entrega 22) e grava o começo dela.
#
# Recebida: toca primeiro para o dono do negócio aberto de quem liga, depois soma os vendedores do estado do
# número chamado e por fim todos; cada etapa toca RING_SECONDS. A resposta vai como texto simples para o
# plano de discagem: "segundos|etapa1|etapa2|etapa3", cada etapa "PJSIP/201&PJSIP/202".
#
# Feita: só número nacional (ou 0800/0300/400X); sai com o número do estado do vendedor. A resposta é
# "número de saída|número discado"; vazia recusa (internacional, 0900, ramal desligado).
class Outsider::Voice::Router
  PhoneNumber = Outsider::Voice::PhoneNumber

  def initialize(settings)
    @settings = settings
    @account = settings.account
  end

  # did: o número que a operadora pôs no pedido; algumas põem ali o usuário da conta e o número só no "To"
  def inbound(linkedid:, did:, from:, to: nil)
    number = @settings.number_for(did) || @settings.number_for(to.to_s[/sip:\+?([^@;>]+)@/, 1])
    contact = PhoneNumber.find_contact(@account, from)
    deal = open_deal(contact)
    create_call(linkedid, direction: :inbound, from_number: PhoneNumber.e164(from) || PhoneNumber.digits(from),
                          to_number: number&.dig('number'), did: number&.dig('number') || PhoneNumber.digits(did),
                          state_code: number&.dig('state'), contact: contact, opportunity: deal)
    plan(deal&.owner_id, number&.dig('state'))
  end

  def outbound(linkedid:, extension:, number:)
    user_id = @settings.user_id_for_extension(extension)
    national = PhoneNumber.national(number)
    return '' unless user_id && national

    state = @settings.agent_for(user_id)['state']
    line = @settings.number_for_state(state)
    contact = PhoneNumber.find_contact(@account, national)
    create_call(linkedid, direction: :outbound, user_id: user_id, from_number: line&.dig('number'), to_number: PhoneNumber.e164(national) || national,
                          did: line&.dig('number'), state_code: line&.dig('state'), contact: contact, opportunity: open_deal(contact))
    "#{line&.dig('number')}|#{dial_string(national)}"
  end

  def internal(linkedid:, extension:, target:)
    create_call(linkedid, direction: :internal, user_id: @settings.user_id_for_extension(extension), from_number: extension.to_s,
                          to_number: target.to_s)
  end

  private

  def create_call(linkedid, **attributes)
    Outsider::Voice::Call.create_with(account: @account, started_at: Time.current, **attributes).find_or_create_by!(linkedid: linkedid)
  end

  def open_deal(contact)
    return unless contact

    Outsider::Crm::Opportunity.where(account_id: @account.id, contact_id: contact.id).open.order(updated_at: :desc).first
  end

  # cada etapa soma gente à anterior: o dono continua tocando quando entram os do estado. Sem "tocar primeiro
  # para o dono" nas Configurações, começa pelos do estado (o dono do estado está entre eles)
  def plan(owner_id, state)
    agents = @settings.enabled_agents
    owner = @settings.data['owner_first'] ? [agents.dig(owner_id, 'extension')].compact : []
    local = owner + agents.values.select { |agent| agent['state'] == state }.pluck('extension')
    steps = [owner, local, local + agents.values.pluck('extension')].map(&:uniq).reject(&:empty?).uniq
    ([@settings.data['ring_seconds']] + steps.map { |step| step.map { |extension| "PJSIP/#{extension}" }.join('&') }).join('|')
  end

  def dial_string(national)
    return national if national.match?(PhoneNumber::SPECIAL)

    { 'ddd' => national, 'zero_ddd' => "0#{national}", 'country' => "55#{national}" }.fetch(@settings.data['dial_format'])
  end
end
