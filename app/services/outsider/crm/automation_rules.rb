# OUTSIDER: regras de automação "quando acontecer X, faça Y" montadas pelo administrador.
# Ficam em accounts.internal_attributes (como as configurações do CRM), sem tabela nova: são poucas
# por conta e mudam pouco. Quem executa é o Outsider::Crm::RuleRunner (eventos do negócio) e o
# Outsider::Crm::TimedRules (verificação de hora em hora).
#
# Regra: { id, name, active, trigger, wait_hours, conditions: { business_unit_id, pipeline_id,
# stage_id, min_value_cents, lost_reason_id }, actions: [{ type, ... }] }. Nenhuma ação muda etapa
# do negócio. A única que muda a situação é "encaminhar" (só em "quando perder"): o perdido vira
# encaminhado e nasce um negócio na outra unidade, que pode disparar as regras de "criado" de lá; o
# limite de tentativas por jornada impede um vai e volta sem fim.
class Outsider::Crm::AutomationRules
  KEY = 'outsider_crm_rules'.freeze
  # id nunca reaproveitado: a linha do tempo guarda o id da regra para não repetir a mesma situação
  NEXT_ID_KEY = 'outsider_crm_rules_next_id'.freeze
  EVENT_TRIGGERS = %w[created stage_entered won lost].freeze
  TIMED_TRIGGERS = %w[stalled no_next_task].freeze
  TRIGGERS = (EVENT_TRIGGERS + TIMED_TRIGGERS).freeze
  ACTION_TYPES = %w[create_task set_owner add_label add_note forward].freeze
  # gatilhos em que dá para encaminhar e filtrar pelo motivo da perda
  LOST_ONLY = %w[lost].freeze
  ASSIGNEES = %w[owner managers user].freeze
  MAX_RULES = 30
  MAX_ACTIONS = 5
  MAX_HOURS = 2160 # 90 dias

  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.join(', '))
    end
  end

  def initialize(account)
    @account = account
  end

  def all
    Array(@account.internal_attributes[KEY])
  end

  def active(triggers)
    all.select { |rule| rule['active'] && Array(triggers).include?(rule['trigger']) }
  end

  def find(id)
    all.find { |rule| rule['id'] == id.to_i } || raise(ActiveRecord::RecordNotFound)
  end

  def create(attributes)
    save do |rules|
      raise Invalid, ['too_many_rules'] if rules.size >= MAX_RULES

      rule = normalize(attributes).merge('id' => next_id(rules), 'created_at' => Time.current.iso8601)
      [rules + [rule], rule]
    end
  end

  def update(id, attributes)
    attributes = attributes.to_h.stringify_keys
    save do |rules|
      current = rules.find { |rule| rule['id'] == id.to_i } || raise(ActiveRecord::RecordNotFound)
      rule = changed(current, attributes)
      [rules.map { |item| item['id'] == rule['id'] ? rule : item }, rule]
    end
  end

  def destroy(id)
    save do |rules|
      rule = rules.find { |item| item['id'] == id.to_i } || raise(ActiveRecord::RecordNotFound)
      [rules - [rule], rule]
    end
  end

  private

  # Só ligar/desligar não revalida o resto: dá para desligar uma regra cuja etiqueta ou etapa sumiu
  def changed(current, attributes)
    if attributes.keys == ['active']
      current.merge('active' => ActiveModel::Type::Boolean.new.cast(attributes['active']) || false, 'updated_at' => Time.current.iso8601)
    else
      current.merge(normalize(current.merge(attributes)))
    end
  end

  def next_id(rules)
    [@account.internal_attributes[NEXT_ID_KEY].to_i, rules.pluck('id').max.to_i + 1].max
  end

  def save
    @account.with_lock do
      rules, result = yield(all)
      attributes = { KEY => rules, NEXT_ID_KEY => [next_id(rules), result['id'] + 1].max }
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(attributes)) # rubocop:disable Rails/SkipsModelValidations
      result
    end
  end

  def normalize(attributes)
    Outsider::Crm::AutomationRuleValidator.new(@account, attributes.to_h.deep_stringify_keys).normalize
  end
end
