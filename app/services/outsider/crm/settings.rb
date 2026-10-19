# OUTSIDER: configurações do CRM por conta. Ficam em accounts.internal_attributes, como as
# permissões da página Status, para não precisar de coluna nova numa tabela do Chatwoot.
class Outsider::Crm::Settings
  KEY = 'outsider_crm_settings'.freeze
  DEFAULTS = { 'max_forward_attempts' => 3 }.freeze
  LIMITS = { 'max_forward_attempts' => 1..10 }.freeze

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
    values = values.to_h.stringify_keys.slice(*DEFAULTS.keys).transform_values { |value| Integer(value, exception: false) }
    invalid = values.reject { |name, value| value && LIMITS[name].cover?(value) }
    raise Invalid, invalid.keys.join(', ') if invalid.any?

    @account.with_lock do
      merged = @account.internal_attributes.merge(KEY => to_h.merge(values))
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: merged) # rubocop:disable Rails/SkipsModelValidations
    end
    to_h
  end
end
