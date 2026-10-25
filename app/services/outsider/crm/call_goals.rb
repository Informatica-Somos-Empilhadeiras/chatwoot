# OUTSIDER: metas mensais de ligação por vendedor (Entrega 22): ligações feitas e minutos em ligação no mês.
# Mesma regra das metas de venda (MonthlyConfig): o que vale para um mês vale para os seguintes até a próxima
# alteração. Vazio ou zero = sem meta.
class Outsider::Crm::CallGoals < Outsider::Crm::MonthlyConfig
  KEY = 'outsider_voice_goals'.freeze
  FIELDS = %w[calls minutes].freeze
  MAX = 100_000

  def for_month(month)
    from, data = version(month)
    { 'month' => month, 'from' => from, 'users' => data['users'].to_h }
  end

  def update(month, users:)
    raise Invalid, ['month'] unless month.to_s.match?(MONTH)

    @errors = []
    data = { 'users' => clean(users) }
    raise Invalid, @errors if @errors.any?

    store(month, data)
    for_month(month)
  end

  private

  def clean(users)
    users.to_h.each_with_object({}) do |(id, goals), result|
      next @errors << "users.#{id}" unless user_ids.include?(id.to_i)

      row = FIELDS.index_with { |field| goal(id, field, goals.to_h[field]) }.compact
      result[id.to_i.to_s] = row if row.any?
    end
  end

  # vazio ou zero: sem meta
  def goal(id, field, value)
    return if value.blank? || value.to_s == '0'

    number = Integer(value, exception: false)
    return number if number&.between?(1, MAX)

    @errors << "users.#{id}.#{field}"
    nil
  end
end
