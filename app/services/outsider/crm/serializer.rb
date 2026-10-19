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

  def opportunity(opportunity, access: nil)
    opportunity.slice(
      :id, :display_id, :title, :value_cents, :currency, :expected_close_on, :probability, :status,
      :business_unit_id, :pipeline_id, :stage_id, :journey_id, :conversation_id, :lost_reason_id,
      :custom_fields, :position, :closed_at, :stage_changed_at, :created_at, :updated_at
    ).merge(
      code: opportunity.code,
      effective_probability: opportunity.effective_probability,
      overdue: opportunity.open? && opportunity.expected_close_on.present? && opportunity.expected_close_on < Time.zone.today,
      sla_exceeded: sla_exceeded?(opportunity),
      contact: contact(opportunity.contact),
      owner: user(opportunity.owner),
      can_edit: access&.edit_opportunity?(opportunity)
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
