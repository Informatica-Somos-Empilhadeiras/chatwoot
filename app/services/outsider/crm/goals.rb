# OUTSIDER: metas mensais de venda (valor ganho no mês, em centavos) por unidade e por vendedor.
# A meta gravada para um mês vale para ele e os seguintes, até a próxima alteração (ver
# MonthlyConfig). Meta vazia ou zero = sem meta.
class Outsider::Crm::Goals < Outsider::Crm::MonthlyConfig
  KEY = 'outsider_crm_goals'.freeze
  MAX_CENTS = 100_000_000_000 # R$ 1 bilhão

  def for_month(month)
    from, data = version(month)
    { 'month' => month, 'from' => from, 'units' => data['units'].to_h, 'users' => data['users'].to_h }
  end

  def update(month, units:, users:)
    raise Invalid, ['month'] unless month.to_s.match?(MONTH)

    @errors = []
    data = { 'units' => clean(units, unit_ids, 'units'), 'users' => clean(users, user_ids, 'users') }
    raise Invalid, @errors if @errors.any?

    store(month, data)
    for_month(month)
  end

  private

  def clean(values, valid_ids, field)
    values.to_h.each_with_object({}) do |(id, cents), result|
      next if cents.blank? || cents.to_s == '0'

      number = Integer(cents, exception: false)
      if number&.between?(1, MAX_CENTS) && valid_ids.include?(id.to_i)
        result[id.to_i.to_s] = number
      else
        @errors << "#{field}.#{id}"
      end
    end
  end
end
