# OUTSIDER: o que a tela "Encaminhar para outra unidade" precisa saber antes de confirmar: para
# quais unidades dá para mandar (e por que não, quando não dá, com o link do negócio que bloqueia),
# pipelines e possíveis responsáveis de cada uma, motivos, tentativa atual contra o limite e o
# caminho da jornada até aqui (por que a tentativa não é a primeira), tarefas pendentes e a conversa.
class Outsider::Crm::ForwardOptions
  ROLE_ORDER = { 'manager' => 0, 'seller' => 1, 'administrator' => 2 }.freeze

  def initialize(opportunity, access:, user:)
    @opportunity = opportunity
    @access = access
    @user = user
    @forwarder = Outsider::Crm::OpportunityForwarder.new(opportunity, access: access, user: user, params: {})
  end

  def to_h
    used = @forwarder.attempts_used
    max = @forwarder.max_attempts
    {
      opportunity_id: @opportunity.id,
      attempts: { used: used, max: max, next: used + 1, limit_reached: used >= max },
      journey: journey_path,
      reason_required: Outsider::Crm::OpportunityForwarder.reason_required?(account_id),
      reasons: Outsider::Crm::OpportunityForwarder.reasons(account_id).map { |reason| reason.slice(:id, :name) },
      pending_tasks: @opportunity.tasks.pending.count,
      conversation: conversation,
      units: units.map { |unit| unit_option(unit) }
    }
  end

  private

  def account_id
    @opportunity.account_id
  end

  def units
    Outsider::Crm::BusinessUnit.active.ordered.where(account_id: account_id).where.not(id: @opportunity.business_unit_id)
  end

  def unit_option(unit)
    pipelines = active_pipelines.fetch(unit.id, [])
    unavailable = unavailable_reason(unit, pipelines)
    blocking = open_deals[unit.id]
    {
      id: unit.id, name: unit.name, available: unavailable.nil?, unavailable_reason: unavailable,
      open_opportunity_code: blocking&.code, open_opportunity_id: blocking&.id,
      open_opportunity_can_view: blocking.present? && @access.view_opportunity?(blocking),
      pipelines: pipelines.map { |pipeline| pipeline.slice(:id, :name) },
      members: members(unit.id)
    }
  end

  # Negócios da jornada em ordem (unidade, código, situação): o limite conta os encaminhamentos dela
  def journey_path
    @opportunity.journey.opportunities.includes(:business_unit).order(:id).map do |item|
      { id: item.id, code: item.code, status: item.status, unit: item.business_unit.name, can_view: @access.view_opportunity?(item) }
    end
  end

  def unavailable_reason(unit, pipelines)
    return 'open_opportunity' if open_deals.key?(unit.id)

    'no_pipeline' if pipelines.empty?
  end

  def active_pipelines
    @active_pipelines ||= Outsider::Crm::Pipeline.active.ordered.where(account_id: account_id).group_by(&:business_unit_id)
  end

  def open_deals
    @open_deals ||= Outsider::Crm::Opportunity.open.where(account_id: account_id, contact_id: @opportunity.contact_id)
                                              .index_by(&:business_unit_id)
  end

  # Membros da unidade e administradores da conta; in_inbox diz se a pessoa enxerga a conversa
  # (só assim dá para atribuí-la a ela)
  def members(unit_id)
    roles = Outsider::Crm::BusinessUnitMember.where(account_id: account_id, business_unit_id: unit_id).pluck(:user_id, :role).to_h
    users = User.where(id: @access.assignable_user_ids(unit_id)).map do |user|
      role = roles[user.id] || 'administrator'
      { id: user.id, name: user.name, thumbnail: user.avatar_url, role: role, in_inbox: inbox_agent_ids.include?(user.id) }
    end
    users.sort_by { |member| [ROLE_ORDER.fetch(member[:role], 3), member[:name].to_s.downcase] }
  end

  def inbox_agent_ids
    @inbox_agent_ids ||= @opportunity.conversation ? @opportunity.conversation.inbox.assignable_agents.map(&:id) : []
  end

  def conversation
    conversation = @opportunity.conversation
    return if conversation.nil?

    {
      display_id: conversation.display_id,
      inbox_name: conversation.inbox.name,
      assignee: conversation.assignee&.slice(:id, :name),
      can_assign: inbox_agent_ids.include?(@user.id)
    }
  end
end
