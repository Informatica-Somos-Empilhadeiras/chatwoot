# OUTSIDER: aba Metas do CRM. No mês escolhido: quanto cada unidade e cada vendedor ganhou contra a
# meta (Goals) e a comissão de cada vendedor (Commission), negócio por negócio. Administrador e
# gestor veem as unidades que acompanham e os vendedores delas; vendedor vê só os próprios números e
# o cálculo da comissão dele ("me").
#
# Conta o negócio ganho no mês (closed_at), pelo responsável atual. O vendedor visto por um gestor
# soma só os negócios das unidades que esse gestor acompanha. mine_only (resumo da tela principal)
# devolve só os números da própria pessoa.
class Outsider::Crm::Performance
  def initialize(access, month, mine_only: false)
    @access = access
    @month = month
    @mine_only = mine_only
    @account = access.account_user.account
    @user_id = access.account_user.user_id
  end

  def to_h
    return { month: @month, from: range.begin.to_date, to: range.end.to_date, me: me } if @mine_only

    {
      month: @month, from: range.begin.to_date, to: range.end.to_date, manager: @access.manager?,
      goals_from: goals['from'], commission_from: commission['from'], general_bp: commission['general_bp'],
      me: me, units: units, sellers: sellers, totals: totals
    }
  end

  private

  def range
    @range ||= Outsider::Crm::MonthlyConfig.range(@month)
  end

  def goals
    @goals ||= Outsider::Crm::Goals.new(@account).for_month(@month)
  end

  def commission
    @commission ||= Outsider::Crm::Commission.new(@account).for_month(@month)
  end

  def won
    @won ||= @access.metrics(@access.opportunities).won.where(closed_at: range)
                    .includes(:contact, :business_unit).order(:closed_at).to_a
  end

  def full_unit_ids
    @full_unit_ids ||= @access.full_unit_ids
  end

  def managed_won
    won.select { |opportunity| full_unit_ids.include?(opportunity.business_unit_id) }
  end

  def rate(opportunity)
    Outsider::Crm::Commission.rate(commission, opportunity.owner_id, opportunity.business_unit_id)
  end

  def commission_of(deals)
    deals.sum { |deal| Outsider::Crm::Commission.amount(deal.value_cents, rate(deal)) }
  end

  def goal(kind, id)
    goals[kind][id.to_s]
  end

  # Os próprios números: aparece para o vendedor sempre e para o gestor quando ele vende ou tem meta
  def me
    deals = won.select { |opportunity| opportunity.owner_id == @user_id }
    return if @access.manager? && deals.empty? && goal('users', @user_id).nil?

    person(@user_id, deals).merge(deals: deals.map { |deal| deal_json(deal) })
  end

  def units
    return [] unless @access.manager?

    @units ||= unit_rows
  end

  def unit_rows
    by_unit = managed_won.group_by(&:business_unit_id)
    Outsider::Crm::BusinessUnit.where(account_id: @account.id, id: full_unit_ids).ordered.filter_map do |unit|
      deals = by_unit.fetch(unit.id, [])
      next if !unit.active && deals.empty?

      { id: unit.id, name: unit.name, won_cents: deals.sum(&:value_cents), won_count: deals.size, goal_cents: goal('units', unit.id) }
    end
  end

  def sellers
    return [] unless @access.manager?

    by_owner = managed_won.select(&:owner_id).group_by(&:owner_id)
    members = Outsider::Crm::BusinessUnitMember.where(account_id: @account.id, business_unit_id: full_unit_ids).pluck(:user_id)
    User.where(id: (members + by_owner.keys).uniq).map { |user| person(user.id, by_owner.fetch(user.id, []), user) }
        .sort_by { |row| [-row[:won_cents], row[:name].to_s.downcase] }
  end

  def person(user_id, deals, user = nil)
    user ||= User.find_by(id: user_id)
    {
      id: user_id, name: user&.name, thumbnail: user&.avatar_url, won_cents: deals.sum(&:value_cents), won_count: deals.size,
      goal_cents: goal('users', user_id), commission_cents: commission_of(deals)
    }
  end

  def totals
    return unless @access.manager?

    unit_goals = units.filter_map { |unit| unit[:goal_cents] }
    { won_cents: managed_won.sum(&:value_cents), won_count: managed_won.size, goal_cents: unit_goals.sum.nonzero?,
      commission_cents: commission_of(managed_won.select(&:owner_id)) }
  end

  def deal_json(deal)
    basis_points = rate(deal)
    {
      id: deal.id, code: deal.code, title: deal.title, contact_name: deal.contact&.name, business_unit_name: deal.business_unit.name,
      closed_at: deal.closed_at, value_cents: deal.value_cents, bp: basis_points,
      commission_cents: Outsider::Crm::Commission.amount(deal.value_cents, basis_points)
    }
  end
end
