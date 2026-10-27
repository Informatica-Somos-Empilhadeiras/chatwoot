# OUTSIDER: painel de ligações do CRM (Entrega 22). No mês escolhido e hoje: ligações feitas e atendidas pelo
# cliente, recebidas atendidas e perdidas, minutos em ligação e a fila de retorno, com as metas de cada
# vendedor (CallGoals). A meta do dia é a do mês dividida pelos dias úteis (segunda a sexta).
#
# Administrador e gestor veem todos os vendedores com ramal; vendedor vê só os próprios números. Mês e "hoje" no
# fuso da telefonia (Entrega 24).
class Outsider::Voice::Stats
  def initialize(access, month)
    @access = access
    @month = month
    @account = access.account_user.account
    @user_id = access.account_user.user_id
    @settings = Outsider::Voice::Settings.new(@account)
  end

  def to_h
    {
      month: @month, from: range.begin.to_date, to: range.end.to_date, business_days: business_days(range),
      business_days_left: business_days([today, range.begin.to_date].max..range.end.to_date), goals_from: goals['from'],
      manager: @access.manager?,
      totals: totals(month_calls), today: totals(today_calls), sellers: sellers
    }
  end

  private

  def range
    @range ||= Date.strptime(@month, '%Y-%m').in_time_zone(zone).all_month
  end

  def zone
    @settings.time_zone
  end

  def today
    Time.current.in_time_zone(zone).to_date
  end

  def local_date(call)
    call.started_at.in_time_zone(zone).to_date
  end

  def goals
    @goals ||= Outsider::Crm::CallGoals.new(@account).for_month(@month)
  end

  def calls
    Outsider::Voice::Call.where(account_id: @account.id).external
  end

  def month_calls
    @month_calls ||= visible(calls.where(started_at: range)).to_a
  end

  def today_calls
    return [] unless range.cover?(Time.current)

    month_calls.select { |call| local_date(call) == today }
  end

  def visible(scope)
    return scope if @access.manager?

    Outsider::Voice::CallAccess.new(@access, @settings).scope(scope)
  end

  # só recebida fica perdida
  def totals(list)
    missed = list.select(&:missed?)
    person_totals(list).merge(inbound: list.count(&:inbound?), missed: missed.size, to_return: missed.count { |call| call.returned_at.nil? })
  end

  def sellers
    ids = @access.manager? ? (@settings.enabled_agents.keys + month_calls.filter_map(&:user_id)).uniq : [@user_id]
    online = Outsider::Voice::CentralStatus.new(@account).to_h[:extensions]
    by_user = month_calls.group_by(&:user_id)
    User.where(id: ids).order(:name).map { |user| seller(user, by_user.fetch(user.id, []), online) }
  end

  def seller(user, list, online)
    agent = @settings.data['agents'][user.id.to_s] || {}
    today_list = list.select { |call| local_date(call) == today }
    {
      id: user.id, name: user.name, thumbnail: user.avatar_url, extension: agent['extension'], state: agent['state'],
      online: online.include?(agent['extension']), month: person_totals(list), today: person_totals(today_list),
      goal: goals['users'][user.id.to_s] || {}
    }
  end

  def person_totals(list)
    outbound = list.select(&:outbound?)
    inbound = list.select(&:inbound?)
    { outbound: outbound.size, outbound_answered: outbound.count(&:answered?), inbound_answered: inbound.count(&:answered?),
      talk_seconds: list.sum(&:talk_seconds) }
  end

  def business_days(dates)
    (dates.begin.to_date..dates.end.to_date).count(&:on_weekday?)
  end
end
