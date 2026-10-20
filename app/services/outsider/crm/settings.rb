# OUTSIDER: configurações do CRM por conta. Ficam em accounts.internal_attributes, como as
# permissões da página Status, para não precisar de coluna nova numa tabela do Chatwoot.
# As automações (Outsider::Crm::Automations e StalledOpportunities) começam desligadas.
class Outsider::Crm::Settings
  KEY = 'outsider_crm_settings'.freeze
  # nome => [tipo, padrão, faixa aceita]
  FIELDS = {
    'max_forward_attempts' => [:integer, 3, 1..10],
    'automation_won_label' => [:label, nil],
    'automation_lost_label' => [:label, nil],
    'automation_close_tasks' => [:boolean, false],
    'automation_stalled_task' => [:boolean, false],
    'automation_stalled_days' => [:integer, 7, 1..90],
    'highlight_no_next_task' => [:boolean, false],
    # vendedor vê só os próprios negócios e os sem responsável (gestor e administrador veem todos)
    'sellers_see_own_deals' => [:boolean, false]
  }.freeze
  DEFAULTS = FIELDS.transform_values(&:second).freeze
  INVALID = Object.new.freeze

  class Invalid < StandardError; end

  def initialize(account)
    @account = account
  end

  def to_h
    DEFAULTS.merge(@account.internal_attributes.fetch(KEY, {}).slice(*DEFAULTS.keys))
  end

  def [](name)
    to_h.fetch(name.to_s)
  end

  def update(values)
    values = values.to_h.stringify_keys.slice(*DEFAULTS.keys).to_h { |name, value| [name, cast(name, value)] }
    invalid = values.select { |_name, value| value.equal?(INVALID) }
    raise Invalid, invalid.keys.join(', ') if invalid.any?

    @account.with_lock do
      merged = @account.internal_attributes.merge(KEY => to_h.merge(values))
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: merged) # rubocop:disable Rails/SkipsModelValidations
    end
    to_h
  end

  private

  def cast(name, value)
    type, _default, range = FIELDS.fetch(name)
    case type
    when :integer
      number = Integer(value, exception: false)
      number && range.cover?(number) ? number : INVALID
    when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
    when :label then label(value)
    end
  end

  # Etiqueta do Chatwoot pelo nome; vazio desliga a automação
  def label(value)
    title = value.to_s.strip.downcase.presence
    return if title.nil?

    @account.labels.exists?(title: title) ? title : INVALID
  end
end
