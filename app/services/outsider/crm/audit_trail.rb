# OUTSIDER: auditoria de uma oportunidade a partir da tabela audits do Chatwoot (gem audited): as
# alterações do negócio, as das tarefas dele (inclusive apagadas) e as notas apagadas, com autor
# e horário. Troca ids por nomes e esconde campos técnicos, para a tela mostrar
# "Etapa: Proposta → Negociação".
class Outsider::Crm::AuditTrail
  SUBJECTS = {
    'Outsider::Crm::Opportunity' => 'opportunity',
    'Outsider::Crm::Task' => 'task',
    'Outsider::Crm::Activity' => 'note'
  }.freeze

  HIDDEN = %w[
    id account_id opportunity_id created_at updated_at display_id position stage_changed_at closed_at journey_id
    created_by_id completed_by_id currency contact_id conversation_id forwarded_from_id user_id message_id metadata
  ].freeze

  NAMED = {
    'stage_id' => 'Outsider::Crm::Stage', 'pipeline_id' => 'Outsider::Crm::Pipeline',
    'business_unit_id' => 'Outsider::Crm::BusinessUnit', 'lost_reason_id' => 'Outsider::Crm::LostReason',
    'owner_id' => 'User', 'assignee_id' => 'User'
  }.freeze

  def initialize(opportunity)
    @opportunity = opportunity
    @names = {}
  end

  def to_a(limit: 200)
    scope.includes(:user).order(created_at: :desc, id: :desc).limit(limit).map { |audit| present(audit) }
  end

  private

  def scope
    audits = Audited::Audit
    audits.where(auditable_type: 'Outsider::Crm::Opportunity', auditable_id: @opportunity.id)
          .or(audits.where(auditable_type: 'Outsider::Crm::Task', auditable_id: task_titles.keys))
          .or(audits.where(auditable_type: 'Outsider::Crm::Activity', action: 'destroy')
                    .where("audited_changes->>'opportunity_id' = ?", @opportunity.id.to_s))
  end

  # Tarefas atuais e as já apagadas (o registro de criação guarda a oportunidade e o título)
  def task_titles
    @task_titles ||= Audited::Audit.where(auditable_type: 'Outsider::Crm::Task', action: 'create')
                                   .where("audited_changes->>'opportunity_id' = ?", @opportunity.id.to_s)
                                   .pluck(:auditable_id, Arel.sql("audited_changes->>'title'")).to_h
                                   .merge(@opportunity.tasks.pluck(:id, :title).to_h)
  end

  def present(audit)
    {
      id: audit.id,
      action: audit.action,
      subject: SUBJECTS[audit.auditable_type],
      subject_label: subject_label(audit),
      user: audit.user.is_a?(User) ? audit.user.slice(:id, :name) : nil,
      created_at: audit.created_at,
      changes: changes(audit)
    }
  end

  def subject_label(audit)
    case audit.auditable_type
    when 'Outsider::Crm::Task' then value_at(audit, 'title') || task_titles[audit.auditable_id]
    when 'Outsider::Crm::Activity' then value_at(audit, 'body').to_s.truncate(80)
    end
  end

  def value_at(audit, field)
    value = audit.audited_changes[field]
    audit.action == 'update' && value.is_a?(Array) ? value.last : value
  end

  # create e destroy guardam o valor; update guarda [antes, depois]. De nota só interessa o texto.
  def changes(audit)
    model = audit.auditable_type.safe_constantize
    fields = audit.auditable_type == 'Outsider::Crm::Activity' ? audit.audited_changes.slice('body') : audit.audited_changes.except(*HIDDEN)
    fields.flat_map do |field, value|
      from, to = audit.action == 'update' ? Array.wrap(value).values_at(0, 1) : [nil, value]
      next custom_field_changes(from, to) if field == 'custom_fields'
      next [] if audit.action != 'update' && to.blank?

      [{ field: field, from: readable(model, field, from), to: readable(model, field, to) }]
    end
  end

  def custom_field_changes(from, to)
    from ||= {}
    to ||= {}
    (from.keys | to.keys).filter_map do |key|
      next if from[key] == to[key]

      { field: 'custom_fields', label: custom_field_labels[key] || key, from: from[key], to: to[key] }
    end
  end

  def readable(model, field, value)
    return if value.nil?
    return name_for(NAMED[field], value) if NAMED.key?(field)

    enum = model&.defined_enums&.dig(field)
    return enum.key(value) || value if enum

    value
  end

  def name_for(class_name, id)
    @names[[class_name, id]] ||= begin
      record = class_name.constantize.find_by(id: id)
      record.respond_to?(:name) ? record.name : "##{id}"
    end
  end

  def custom_field_labels
    @custom_field_labels ||= Outsider::Crm::CustomFieldDefinition.where(account_id: @opportunity.account_id).pluck(:key, :label).to_h
  end
end
