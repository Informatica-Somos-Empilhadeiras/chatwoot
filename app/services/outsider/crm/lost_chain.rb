# OUTSIDER: "repasse em sequência" (Configurações > Automações, começa desligado). Negócio perdido
# numa unidade segue sozinho para a próxima unidade da ordem escolhida pelo administrador; perdido
# lá, segue para a seguinte, até alguém ganhar ou acabarem as unidades (ou o limite de
# encaminhamentos da conta, em Geral). A ordem dá a volta: perdido na 2ª, tenta a 3ª, a 4ª e depois
# a 1ª. Pula a unidade por onde o cliente já passou nesta jornada, a que já tem negócio aberto dele
# e a que não tem pipeline ativo. Não repassa quando o motivo da perda está na lista de exceções
# (ex.: "cliente desistiu").
#
# No destino, o negócio fica sem responsável e todos da unidade recebem o aviso, para um vendedor
# pegar (botão "Pegar"); ou, no modo rodízio, vai para o próximo vendedor da unidade, com a tarefa
# "Contatar cliente". O negócio de origem continua perdido (conta nas perdas da unidade) e fica
# travado, com o link para o novo; o que aconteceu fica na linha do tempo dele. Roda depois das
# regras de automação: se uma regra já encaminhou o negócio, não faz nada. Nada é enviado ao cliente.
class Outsider::Crm::LostChain
  def initialize(opportunity)
    @opportunity = opportunity
    @settings = Outsider::Crm::Settings.new(opportunity.account)
  end

  def enabled?
    @settings[:chain_enabled] && @settings[:chain_unit_ids].any?
  end

  def perform
    return unless enabled? && @opportunity.lost?
    return if @settings[:chain_skip_reason_ids].include?(@opportunity.lost_reason_id)
    return if Outsider::Crm::Forward.exists?(from_opportunity_id: @opportunity.id)

    Outsider::Crm::Automations.as_system(@opportunity) do
      unit = upcoming_units.first
      unit ? forward_to(unit) : log(exhausted: true)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @opportunity.account).capture_exception
  end

  # Próximas unidades da ordem a partir da unidade do negócio, sem as que seriam puladas. A jornada
  # aberta mostra essa lista como "próximas" no caminho entre unidades (ContactHistory).
  def upcoming_units
    order = @settings[:chain_unit_ids]
    start = order.index(@opportunity.business_unit_id)
    order = order[(start + 1)..] + order[0...start] if start
    units = Outsider::Crm::BusinessUnit.active.where(account_id: @opportunity.account_id, id: order).index_by(&:id)
    order.filter_map { |id| units[id] }.select { |unit| available?(unit) }
  end

  private

  def forward_to(unit)
    forwarder = nil
    Outsider::Crm::Opportunity.transaction do
      owner_id = (Outsider::Crm::Rotation.new(@opportunity.account).next_user_id!(unit.id) if @settings[:chain_assign] == 'rotation')
      forwarder = Outsider::Crm::OpportunityForwarder.new(@opportunity, access: Outsider::Crm::RuleRunner::SystemAccess.new(@opportunity.account_id),
                                                                        user: nil, params: forward_params(unit, owner_id), lost: :keep)
      forwarder.perform
    end
    # o perdido não muda de situação: avisa as telas abertas que ele agora está travado
    Outsider::Crm::LiveUpdates.record_changed(@opportunity)
    log(forwarded: { unit: unit.name, code: forwarder.target.code, owner: forwarder.target.owner&.name })
  rescue Outsider::Crm::OpportunityForwarder::Refused => e
    log(forward_error: e.code.to_s, unit: unit.name)
  end

  def forward_params(unit, owner_id)
    {
      to_business_unit_id: unit.id, owner_id: owner_id, reason_id: forward_reason_id, complete_tasks: true,
      create_task: owner_id.present?, rule_name: I18n.t('outsider_crm.chain.rule_name')
    }
  end

  # O motivo da perda vira o motivo do encaminhamento quando ele também serve para encaminhar
  def forward_reason_id
    @opportunity.lost_reason_id if @opportunity.lost_reason&.kind.in?(%w[forward both])
  end

  def available?(unit)
    visited_unit_ids.exclude?(unit.id) && open_unit_ids.exclude?(unit.id) && pipeline_unit_ids.include?(unit.id)
  end

  def visited_unit_ids
    @visited_unit_ids ||= Outsider::Crm::Opportunity.where(journey_id: @opportunity.journey_id).distinct.pluck(:business_unit_id)
  end

  def open_unit_ids
    @open_unit_ids ||= Outsider::Crm::Opportunity.open.where(account_id: @opportunity.account_id, contact_id: @opportunity.contact_id)
                                                 .distinct.pluck(:business_unit_id)
  end

  def pipeline_unit_ids
    @pipeline_unit_ids ||= Outsider::Crm::Pipeline.active.where(account_id: @opportunity.account_id).distinct.pluck(:business_unit_id)
  end

  def log(**metadata)
    Outsider::Crm::Automations.log(@opportunity, 'chain', **metadata)
  end
end
