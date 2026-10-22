# OUTSIDER: formato JSON das entidades do CRM, usado pelos controllers de Outsider::Crm.
module Outsider::Crm::Serializer
  module_function

  def pipeline(pipeline)
    pipeline.slice(:id, :business_unit_id, :name, :active, :position)
            .merge(stages: pipeline.stages.map { |stage| stage(stage) })
  end

  def stage(stage)
    stage.slice(:id, :pipeline_id, :name, :position, :probability, :kind, :color, :sla_hours)
  end

  def lost_reason(reason)
    reason.slice(:id, :name, :kind, :active, :position)
  end

  def custom_field(definition)
    definition.slice(:id, :key, :label, :field_type, :options, :required, :active, :position)
  end

  LIST_PRELOAD = [:conversation, { forwarded_from: :business_unit, outgoing_forward: { to_opportunity: :business_unit } }].freeze

  # Lista de negócios: tarefas pendentes, conversas e encaminhamentos numa consulta só para todos
  def opportunities(list, access: nil)
    list = list.to_a
    ActiveRecord::Associations::Preloader.new(records: list, associations: LIST_PRELOAD).call
    stats = Outsider::Crm::TaskStats.for(list.map(&:id))
    proposals = Outsider::Crm::ProposalStats.for(list.map(&:id), access)
    list.map do |opportunity|
      opportunity(opportunity, access: access, task_stats: stats[opportunity.id], proposal: proposals[opportunity.id] || false)
    end
  end

  # conversation_display_id é o número da conversa que o Chatwoot mostra (e usa nas URLs)
  # proposal: selo da proposta mais recente (ProposalStats); false = já consultado e o negócio não tem
  def opportunity(opportunity, access: nil, task_stats: nil, proposal: nil)
    opportunity.slice(
      :id, :display_id, :title, :value_cents, :currency, :expected_close_on, :probability, :status,
      :business_unit_id, :pipeline_id, :stage_id, :journey_id, :conversation_id, :lost_reason_id,
      :custom_fields, :position, :closed_at, :stage_changed_at, :created_at, :updated_at
    ).merge(
      code: opportunity.code,
      conversation_display_id: opportunity.conversation&.display_id,
      effective_probability: opportunity.effective_probability,
      overdue: close_overdue?(opportunity),
      sla_exceeded: sla_exceeded?(opportunity),
      tasks: task_stats || Outsider::Crm::TaskStats.for([opportunity.id])[opportunity.id],
      proposal: proposal_stats(opportunity, access, proposal),
      contact: contact(opportunity.contact),
      owner: user(opportunity.owner)
    ).merge(permissions(opportunity, access)).merge(forward_links(opportunity))
  end

  def close_overdue?(opportunity)
    opportunity.open? && opportunity.expected_close_on.present? && opportunity.expected_close_on < Time.zone.today
  end

  def proposal_stats(opportunity, access, proposal)
    proposal.nil? ? Outsider::Crm::ProposalStats.for([opportunity.id], access)[opportunity.id] : proposal.presence
  end

  def permissions(opportunity, access)
    {
      can_edit: access&.edit_opportunity?(opportunity),
      can_delete: access&.delete_opportunity?(opportunity),
      can_forward: access&.forward_opportunity?(opportunity),
      can_claim: access&.claim_opportunity?(opportunity)
    }
  end

  # De onde veio e para onde foi um negócio encaminhado ou repassado (a unidade pode ser uma que o
  # usuário não vê)
  def forward_links(opportunity)
    {
      forwarded_from: forward_link(opportunity.forwarded_from),
      forwarded_to: forward_link(opportunity.outgoing_forward&.to_opportunity)
    }
  end

  def forward_link(opportunity)
    opportunity && { id: opportunity.id, code: opportunity.code, business_unit_name: opportunity.business_unit.name }
  end

  def task(task, access: nil)
    task.slice(:id, :opportunity_id, :title, :description, :kind, :due_at, :completed_at, :created_at).merge(
      overdue: task.overdue?,
      assignee: user(task.assignee),
      created_by: user(task.created_by),
      completed_by: user(task.completed_by),
      can_edit: access&.edit_opportunity?(task.opportunity),
      can_complete: access&.complete_task?(task)
    )
  end

  # Tarefa na lista geral (aba Tarefas do CRM): leva junto o negócio e o contato
  def task_with_opportunity(task, access: nil)
    opportunity = task.opportunity
    task(task, access: access).merge(
      opportunity: opportunity.slice(:id, :title, :status, :business_unit_id).merge(
        code: opportunity.code, contact: contact(opportunity.contact)
      )
    )
  end

  def activity(activity, access: nil)
    activity.slice(:id, :opportunity_id, :kind, :body, :metadata, :created_at).merge(
      user: user(activity.user),
      can_delete: access&.delete_activity?(activity)
    )
  end

  def sla_exceeded?(opportunity)
    hours = opportunity.stage&.sla_hours
    opportunity.open? && hours.present? && opportunity.stage_changed_at.present? && opportunity.stage_changed_at < hours.hours.ago
  end

  def contact(contact)
    return if contact.nil?

    contact.slice(:id, :name, :phone_number, :email, :identifier).merge(thumbnail: contact.avatar_url)
  end

  def user(user)
    user&.slice(:id, :name)&.merge(thumbnail: user.avatar_url)
  end
end
