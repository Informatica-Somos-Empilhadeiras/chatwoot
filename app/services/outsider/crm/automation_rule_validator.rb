# OUTSIDER: confere e limpa uma regra de automação antes de gravar (ver AutomationRules). Unidade,
# pipeline, etapa, pessoas e etiquetas precisam existir na conta; o que não se aplica ao gatilho ou
# à ação é descartado. Erros saem como códigos (ex.: "actions.0.title_blank") para a tela traduzir.
class Outsider::Crm::AutomationRuleValidator
  RULES = Outsider::Crm::AutomationRules

  def initialize(account, attributes)
    @account = account
    @attributes = attributes
    @errors = []
  end

  def normalize
    rule = {
      'name' => text(@attributes['name'], 80, 'name'),
      'active' => @attributes.key?('active') ? boolean(@attributes['active']) : true,
      'trigger' => trigger,
      'wait_hours' => wait_hours,
      'conditions' => conditions,
      'actions' => actions,
      'updated_at' => Time.current.iso8601
    }
    raise RULES::Invalid, @errors if @errors.any?

    rule
  end

  private

  def trigger
    value = @attributes['trigger'].to_s
    @errors << 'trigger_invalid' unless RULES::TRIGGERS.include?(value)
    value
  end

  def timed?
    RULES::TIMED_TRIGGERS.include?(@attributes['trigger'].to_s)
  end

  def wait_hours
    return unless timed?

    hours(@attributes['wait_hours'], 'wait_hours', min: 1)
  end

  def conditions
    raw = @attributes['conditions'].to_h
    unit = find_id(Outsider::Crm::BusinessUnit, raw['business_unit_id'], 'conditions.business_unit_id')
    pipeline = pipeline(raw['pipeline_id'], unit)
    {
      'business_unit_id' => unit&.id || pipeline&.business_unit_id,
      'pipeline_id' => pipeline&.id,
      'stage_id' => stage(raw['stage_id'], pipeline)&.id,
      'min_value_cents' => min_value(raw['min_value_cents']),
      'lost_reason_id' => (reason(raw['lost_reason_id'], %w[lost both], 'conditions.lost_reason_id')&.id if lost?)
    }
  end

  def lost?
    RULES::LOST_ONLY.include?(@attributes['trigger'].to_s)
  end

  # O pipeline precisa ser da unidade escolhida
  def pipeline(id, unit)
    found = find_id(Outsider::Crm::Pipeline, id, 'conditions.pipeline_id')
    @errors << 'conditions.pipeline_id' if found && unit && found.business_unit_id != unit.id
    found
  end

  # Etapa só faz sentido dentro de um pipeline, e só as abertas (ganho e perda têm gatilho próprio)
  def stage(id, pipeline)
    return if id.blank?

    found = pipeline&.stages&.find_by(id: id, kind: :open)
    @errors << 'conditions.stage_id' if found.nil?
    found
  end

  def min_value(value)
    return if value.blank?

    number = Integer(value, exception: false)
    return number if number && number >= 0

    @errors << 'conditions.min_value_cents'
    nil
  end

  def actions
    list = Array(@attributes['actions']).first(RULES::MAX_ACTIONS + 1)
    @errors << 'actions_blank' if list.empty?
    @errors << 'too_many_actions' if list.size > RULES::MAX_ACTIONS
    @errors << 'too_many_forwards' if list.count { |action| action.to_h['type'] == 'forward' } > 1
    list.first(RULES::MAX_ACTIONS).each_with_index.map { |action, index| action(action.to_h, "actions.#{index}") }
  end

  def action(raw, prefix)
    case raw['type']
    when 'create_task' then task_action(raw, prefix)
    when 'set_owner' then { 'type' => 'set_owner', 'user_id' => user_id(raw['user_id'], "#{prefix}.user_id") }
    when 'add_label' then { 'type' => 'add_label', 'label' => label(raw['label'], "#{prefix}.label") }
    when 'add_note' then { 'type' => 'add_note', 'body' => text(raw['body'], 2000, "#{prefix}.body") }
    when 'forward' then forward_action(raw, prefix)
    else
      @errors << "#{prefix}.type"
      {}
    end
  end

  def task_action(raw, prefix)
    assignee = RULES::ASSIGNEES.include?(raw['assignee']) ? raw['assignee'] : 'owner'
    kind = Outsider::Crm::Task.kinds.key?(raw['kind']) ? raw['kind'] : 'follow_up'
    {
      'type' => 'create_task', 'title' => text(raw['title'], 255, "#{prefix}.title"), 'kind' => kind,
      'description' => raw['description'].to_s.strip.first(1000).presence,
      'due_in_hours' => hours(raw['due_in_hours'].presence || 0, "#{prefix}.due_in_hours", min: 0),
      'assignee' => assignee, 'user_id' => assignee == 'user' ? user_id(raw['user_id'], "#{prefix}.user_id") : nil
    }
  end

  # Encaminhar só existe em "quando perder". Responsável vazio: o negócio chega sem dono e os gestores
  # da unidade destino recebem o aviso. Motivo vazio: usa o motivo da perda, se ele também servir
  # para encaminhamento.
  def forward_action(raw, prefix)
    @errors << "#{prefix}.forward_trigger" unless lost?
    unit = Outsider::Crm::BusinessUnit.active.find_by(account_id: @account.id, id: raw['to_business_unit_id'])
    @errors << "#{prefix}.to_business_unit_id" if unit.nil?
    {
      'type' => 'forward', 'to_business_unit_id' => unit&.id, 'pipeline_id' => forward_pipeline(raw['pipeline_id'], unit, prefix),
      'reason_id' => reason(raw['reason_id'], %w[forward both], "#{prefix}.reason_id")&.id,
      'owner_id' => forward_owner(raw['owner_id'], unit, prefix), 'create_task' => boolean(raw['create_task']),
      'notes' => raw['notes'].to_s.strip.first(2000).presence
    }
  end

  def forward_pipeline(id, unit, prefix)
    return if id.blank? || unit.nil?

    found = Outsider::Crm::Pipeline.active.find_by(account_id: @account.id, business_unit_id: unit.id, id: id)
    @errors << "#{prefix}.pipeline_id" if found.nil?
    found&.id
  end

  def forward_owner(id, unit, prefix)
    return if id.blank? || unit.nil?
    return id.to_i if Outsider::Crm::Access.assignable_user_ids(@account.id, unit.id).include?(id.to_i)

    @errors << "#{prefix}.owner_id"
    nil
  end

  def reason(id, kinds, field)
    return if id.blank?

    found = Outsider::Crm::LostReason.active.find_by(account_id: @account.id, id: id, kind: kinds)
    @errors << field if found.nil?
    found
  end

  def text(value, limit, field)
    value = value.to_s.strip
    @errors << "#{field}_blank" if value.empty?
    @errors << "#{field}_too_long" if value.length > limit
    value.first(limit)
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def hours(value, field, min:)
    number = Integer(value, exception: false)
    return number if number&.between?(min, RULES::MAX_HOURS)

    @errors << field
    nil
  end

  def find_id(model, id, field)
    return if id.blank?

    found = model.find_by(account_id: @account.id, id: id)
    @errors << field if found.nil?
    found
  end

  def user_id(id, field)
    return id.to_i if id.present? && @account.account_users.exists?(user_id: id)

    @errors << field
    nil
  end

  def label(value, field)
    title = value.to_s.strip.downcase
    return title if title.present? && @account.labels.exists?(title: title)

    @errors << field
    title
  end
end
