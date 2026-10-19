# OUTSIDER: confere os campos personalizados da oportunidade contra as definições da conta:
# só chaves cadastradas, valores do tipo certo e obrigatórios preenchidos.
class Outsider::Crm::CustomFieldsValidator < ActiveModel::Validator
  NUMBER = /\A-?\d+([.,]\d+)?\z/

  def validate(record)
    values = record.custom_fields || {}
    return record.errors.add(:custom_fields, :invalid) unless values.is_a?(Hash)

    definitions = Outsider::Crm::CustomFieldDefinition.where(account_id: record.account_id).to_a
    # campo desativado continua aceito: o valor antigo fica guardado na oportunidade
    unknown = values.keys - definitions.map(&:key)
    add_error(record, :invalid, unknown.join(', ')) if unknown.any?

    definitions.select(&:active?).each { |definition| validate_value(record, definition, values[definition.key]) }
  end

  private

  def validate_value(record, definition, value)
    if value.blank? && value != false
      add_error(record, :blank, definition.label) if definition.required?
    elsif !valid_value?(definition, value)
      add_error(record, :invalid, definition.label)
    end
  end

  def valid_value?(definition, value)
    case definition.field_type
    when 'number', 'currency' then value.is_a?(Numeric) || value.to_s.match?(NUMBER)
    when 'date' then valid_date?(value)
    when 'list' then Array(definition.options).include?(value)
    when 'checkbox' then [true, false].include?(value)
    else value.is_a?(String) && value.length <= 1000
    end
  end

  def valid_date?(value)
    Date.iso8601(value.to_s).present?
  rescue Date::Error
    false
  end

  def add_error(record, type, subject)
    record.errors.add(:custom_fields, type, message: "#{subject}: #{I18n.t("errors.messages.#{type}")}")
  end
end
