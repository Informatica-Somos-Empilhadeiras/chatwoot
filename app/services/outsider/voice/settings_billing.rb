# OUTSIDER: custos das ligações e filiais (Entrega 25), em Telefonia > Configurações, junto com o resto de
# Outsider::Voice::Settings.
#
# Custos: valor por minuto e por ligação atendida para cada tipo de ligação (fixo ou celular, do mesmo DDD da
# linha ou de outro, internacional, 0800/4004 e recebidas) e o jeito que a operadora conta o tempo. O custo é
# calculado na hora (Outsider::Voice::CallCosts): mudar o preço muda também o custo das ligações antigas.
#
# Filiais: nome de cada uma; o vendedor fica numa filial pelo campo "branch" do ramal (Settings#clean_agent).
module Outsider::Voice::SettingsBilling
  RATE_KINDS = %w[local_fixed local_mobile long_fixed long_mobile international special inbound].freeze
  BILLINGS = %w[30_6 60_6 second minute].freeze
  MAX_RATE = 100
  MAX_BRANCHES = 50
  BRANCH_ID = /\A[a-z0-9]{4,12}\z/
  BILLING_FIELDS = %w[costs branches].freeze

  def costs
    stored = data['costs'].to_h
    rates = RATE_KINDS.index_with { |kind| { 'minute' => 0.0, 'call' => 0.0 }.merge(stored.dig('rates', kind).to_h) }
    { 'billing' => BILLINGS.include?(stored['billing']) ? stored['billing'] : BILLINGS.first, 'rates' => rates }
  end

  def branches
    Array(data['branches'])
  end

  def branch_for(user_id)
    id = data['agents'].dig(user_id.to_s, 'branch')
    id && branches.find { |branch| branch['id'] == id }
  end

  private

  # tela antiga que não manda os campos: fica o que está guardado
  def clean_billing(params)
    values = { 'costs' => costs, 'branches' => branches }.merge(params.slice(*BILLING_FIELDS))
    { 'costs' => clean_costs(values['costs'].to_h), 'branches' => clean_branches(Array(values['branches'])) }
  end

  def clean_costs(value)
    billing = choice(value['billing'], BILLINGS, 'costs.billing')
    rates = RATE_KINDS.index_with do |kind|
      rate = value.dig('rates', kind).to_h
      { 'minute' => price(rate['minute'], "costs.rates.#{kind}.minute"), 'call' => price(rate['call'], "costs.rates.#{kind}.call") }
    end
    { 'billing' => billing, 'rates' => rates }
  end

  # R$ com até 4 casas; aceita vírgula ("0,12")
  def price(value, field)
    text = value.to_s.strip.tr(',', '.')
    number = text.empty? ? 0.0 : Float(text, exception: false)
    return number.round(4) if number && number >= 0 && number <= MAX_RATE

    @errors << field
    0.0
  end

  def clean_branches(rows)
    @errors << 'branches' if rows.size > MAX_BRANCHES
    names = []
    @branch_ids = []
    rows.each_with_index.filter_map do |row, index|
      row = row.to_h
      name = row['name'].to_s.strip.first(60)
      next if name.empty? && row['id'].blank?

      @errors << "branches.#{index}.name" if name.empty? || names.include?(name.downcase)
      names << name.downcase
      { 'id' => branch_id(row['id']), 'name' => name }
    end
  end

  # o id que veio da tela, ou um novo para filial nova
  def branch_id(value)
    id = value.to_s.match?(BRANCH_ID) && @branch_ids.exclude?(value) ? value : SecureRandom.alphanumeric(8).downcase
    @branch_ids << id
    id
  end

  # filial do ramal: só uma que existe (filial apagada some do vendedor)
  def clean_branch_id(value)
    (@branch_ids || branches.pluck('id')).include?(value.to_s) ? value.to_s : nil
  end
end
