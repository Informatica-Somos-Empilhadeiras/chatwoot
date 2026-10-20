# OUTSIDER: comissão dos vendedores = valor dos negócios ganhos no mês × percentual. Há um percentual
# geral e percentuais específicos por vendedor, por unidade ou pelos dois juntos; vale o mais
# específico (vendedor + unidade, depois vendedor, depois unidade, depois o geral). Percentual em
# centésimos de ponto (150 = 1,5%). Cada alteração vale a partir do mês em que foi feita; os meses
# anteriores continuam com o percentual da época (ver MonthlyConfig).
class Outsider::Crm::Commission < Outsider::Crm::MonthlyConfig
  KEY = 'outsider_crm_commission'.freeze
  MAX_BP = 10_000
  MAX_RULES = 100

  # ordem de procura: [vendedor, unidade], [vendedor, qualquer], [qualquer, unidade]
  def self.rate(config, user_id, unit_id)
    by_target = config['rules'].index_by { |rule| rule.values_at('user_id', 'business_unit_id') }
    match = [[user_id, unit_id], [user_id, nil], [nil, unit_id]].lazy.filter_map { |key| by_target[key] if key.any? }.first
    match ? match['bp'] : config['general_bp']
  end

  # R$ 1.000,00 a 1% = R$ 10,00
  def self.amount(value_cents, basis_points)
    (value_cents.to_i * basis_points.to_i / 10_000.0).round
  end

  def for_month(month)
    from, data = version(month)
    { 'month' => month, 'from' => from, 'general_bp' => data['general_bp'].to_i, 'rules' => Array(data['rules']) }
  end

  def update(general_bp:, rules:)
    @errors = []
    data = { 'general_bp' => basis_points(general_bp, 'general'), 'rules' => clean_rules(Array(rules)) }
    raise Invalid, @errors if @errors.any?

    store(self.class.current_month, data)
    for_month(self.class.current_month)
  end

  private

  def basis_points(value, field)
    number = Integer(value.presence || 0, exception: false)
    return number if number&.between?(0, MAX_BP)

    @errors << field
    0
  end

  def clean_rules(list)
    @errors << 'too_many_rules' if list.size > MAX_RULES
    rules = list.first(MAX_RULES).each_with_index.map { |raw, index| rule(raw.to_h.stringify_keys, "rules.#{index}") }
    pairs = rules.map { |item| item.values_at('user_id', 'business_unit_id') }
    @errors << 'duplicate_rules' if pairs.uniq.size != pairs.size
    rules
  end

  def rule(raw, prefix)
    user = known(raw['user_id'], user_ids, "#{prefix}.user_id")
    unit = known(raw['business_unit_id'], unit_ids, "#{prefix}.business_unit_id")
    @errors << "#{prefix}.target" if user.nil? && unit.nil?
    { 'user_id' => user, 'business_unit_id' => unit, 'bp' => basis_points(raw['bp'], "#{prefix}.bp") }
  end

  # vazio = qualquer; id que não é da conta vira erro
  def known(value, valid_ids, field)
    id = value.presence&.to_i
    @errors << field unless id.nil? || valid_ids.include?(id)
    id
  end
end
