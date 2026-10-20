# OUTSIDER: "Histórico multiempresa" de um contato: em quais unidades do grupo ele já negociou, o
# resultado de cada tentativa e os encaminhamentos entre elas, jornada por jornada.
# Mostra só o resumo (unidade, código, título, situação, valor, datas, responsável, motivo e a
# observação do encaminhamento), inclusive das unidades que o usuário não acompanha, para quem
# encaminha saber onde o cliente já passou. Tarefas, notas e auditoria continuam só para a unidade
# (can_view diz se o usuário pode abrir o negócio). Com o repasse em sequência ligado, a jornada em
# andamento traz as próximas unidades para onde o negócio aberto vai se for perdido (upcoming, a
# partir de upcoming_from), já cortadas pelo limite de encaminhamentos.
class Outsider::Crm::ContactHistory
  JOURNEYS_LIMIT = 20

  def initialize(contact, access:)
    @contact = contact
    @access = access
  end

  def to_h
    {
      contact_id: @contact.id,
      max_forward_attempts: max_attempts,
      journeys: Outsider::Crm::ContactSummary.group?(@contact) ? [] : journeys.map { |journey| journey_json(journey) }
    }
  end

  private

  def journeys
    Outsider::Crm::Journey.where(account_id: @contact.account_id, contact_id: @contact.id)
                          .order(id: :desc).limit(JOURNEYS_LIMIT)
                          .includes(opportunities: [:business_unit, :owner, :lost_reason],
                                    forwards: [:from_business_unit, :to_business_unit, :reason, :requested_by])
  end

  def max_attempts
    @max_attempts ||= Outsider::Crm::Settings.new(@contact.account)[:max_forward_attempts]
  end

  def journey_json(journey)
    journey.slice(:id, :status, :origin, :created_at, :closed_at).merge(
      forwards_count: journey.forwards.size,
      opportunities: journey.opportunities.sort_by(&:id).map { |opportunity| opportunity_json(opportunity) },
      forwards: journey.forwards.sort_by(&:id).map { |forward| forward_json(forward) }
    ).merge(upcoming(journey))
  end

  # Se o negócio aberto mais recente da jornada for perdido, para onde o repasse em sequência leva
  # (em ordem)
  def upcoming(journey)
    current = journey.opportunities.select(&:open?).max_by(&:id)
    { upcoming: upcoming_units(journey, current), upcoming_from: current&.id }
  end

  def upcoming_units(journey, current)
    return [] if current.nil?

    chain = Outsider::Crm::LostChain.new(current)
    return [] unless chain.enabled?

    left = [max_attempts - journey.forwards.size, 0].max
    chain.upcoming_units.first(left).map { |unit| unit.slice(:id, :name) }
  end

  def opportunity_json(opportunity)
    opportunity.slice(:id, :title, :status, :value_cents, :forwarded_from_id, :created_at, :closed_at).merge(
      code: opportunity.code,
      business_unit: opportunity.business_unit.slice(:id, :name),
      owner: opportunity.owner&.name,
      reason: opportunity.lost_reason&.name,
      can_view: @access.view_opportunity?(opportunity)
    )
  end

  def forward_json(forward)
    forward.slice(:id, :attempt_number, :from_opportunity_id, :to_opportunity_id, :notes, :created_at).merge(
      from_unit: forward.from_business_unit.name,
      to_unit: forward.to_business_unit.name,
      reason: forward.reason&.name,
      requested_by: forward.requested_by&.name
    )
  end
end
