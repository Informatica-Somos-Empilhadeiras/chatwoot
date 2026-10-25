# OUTSIDER: painel (wallboard) da Telefonia (Entrega 23). No período escolhido (hoje, semana, mês ou mês
# anterior): totais de ligações recebidas, feitas e entre ramais, tempos (médio, mais longo, para atender),
# ligações por hora e por dia da semana x hora, quem está em ligação agora e a meta do mês.
#
# Gestor e administrador veem todos ou um vendedor; o vendedor vê só os próprios números. As horas seguem o
# fuso de quem está vendo (enviado pelo navegador).
class Outsider::Voice::Wallboard
  PERIODS = %w[today week month last_month].freeze
  DEFAULT_ZONE = 'America/Sao_Paulo'.freeze
  # ligação sem fim avisado há mais que isso (central reiniciada no meio) não conta como em andamento
  LIVE_WINDOW = 4.hours

  def initialize(access, period:, user_id: nil, zone: nil)
    @access = access
    @account = access.account_user.account
    @period = PERIODS.include?(period) ? period : 'today'
    @zone = ActiveSupport::TimeZone[zone.to_s] || ActiveSupport::TimeZone[DEFAULT_ZONE]
    @user_id = access.manager? ? user_id.presence&.to_i : access.account_user.user_id
    @settings = Outsider::Voice::Settings.new(@account)
  end

  def to_h
    {
      period: @period, from: range.begin.to_date, to: range.end.to_date, user_id: @user_id, manager: @access.manager?,
      summary: summary, by_hour: by_hour, by_weekday_hour: by_weekday_hour, to_return: to_return,
      agents: @access.manager? ? agents : [], live: live, goal: goal
    }
  end

  private

  def range
    @range ||= begin
      now = Time.current.in_time_zone(@zone)
      case @period
      when 'week' then now.all_week
      when 'month' then now.all_month
      when 'last_month' then (now - 1.month).all_month
      else now.all_day
      end
    end
  end

  def scope
    calls = Outsider::Voice::Call.where(account_id: @account.id)
    @user_id ? calls.where(user_id: @user_id) : calls
  end

  # poucas centenas de ligações por dia: as contas são feitas aqui, com as horas no fuso de quem vê
  def calls
    @calls ||= scope.where(started_at: range).to_a
  end

  def summary
    by_direction = calls.group_by(&:direction)
    inbound = by_direction.fetch('inbound', [])
    outbound = by_direction.fetch('outbound', [])
    {
      total: calls.size, inbound: inbound.size, outbound: outbound.size, internal: by_direction.fetch('internal', []).size,
      inbound_answered: inbound.count(&:answered?), missed: inbound.count(&:missed?), outbound_answered: outbound.count(&:answered?)
    }.merge(times(inbound))
  end

  def times(inbound)
    talks = calls.select(&:answered?).map(&:talk_seconds)
    waits = inbound.select(&:answered?).map { |call| (call.answered_at - call.started_at).round }
    { talk_seconds: talks.sum, average_talk: average(talks), longest_talk: talks.max || 0, average_answer: average(waits) }
  end

  def average(values)
    values.empty? ? 0 : (values.sum.to_f / values.size).round
  end

  def by_hour
    rows = Array.new(24) { |hour| { hour: hour, inbound: 0, outbound: 0, internal: 0 } }
    calls.each { |call| rows[call.started_at.in_time_zone(@zone).hour][call.direction.to_sym] += 1 }
    rows
  end

  # [dia da semana (0 = domingo)][hora] = ligações
  def by_weekday_hour
    grid = Array.new(7) { Array.new(24, 0) }
    calls.each do |call|
      time = call.started_at.in_time_zone(@zone)
      grid[time.wday][time.hour] += 1
    end
    grid
  end

  # fila de retorno de agora (não só do período), do jeito que a pessoa vê em Ligações
  def to_return
    Outsider::Voice::CallAccess.new(@access, @settings).scope(Outsider::Voice::Call.where(account_id: @account.id).to_return).count
  end

  def agents
    online = Outsider::Voice::CentralStatus.new(@account).to_h[:extensions]
    in_call = live_calls.filter_map(&:user_id)
    User.where(id: (@settings.enabled_agents.keys + calls_by_user.keys).uniq).order(:name).map do |user|
      extension = @settings.data['agents'].dig(user.id.to_s, 'extension')
      agent_row(user).merge(extension: extension, online: online.include?(extension), in_call: in_call.include?(user.id))
    end
  end

  # todos os vendedores no período, mesmo com um deles escolhido no painel
  def calls_by_user
    @calls_by_user ||= Outsider::Voice::Call.where(account_id: @account.id, started_at: range).where.not(user_id: nil).group_by(&:user_id)
  end

  def agent_row(user)
    list = calls_by_user.fetch(user.id, [])
    { id: user.id, name: user.name, thumbnail: user.avatar_url, total: list.size, outbound: list.count(&:outbound?),
      inbound_answered: list.count { |call| call.inbound? && call.answered? }, talk_seconds: list.select(&:answered?).sum(&:talk_seconds) }
  end

  def live_calls
    @live_calls ||= Outsider::Voice::Call.where(account_id: @account.id, status: %i[ringing answered], ended_at: nil,
                                                started_at: LIVE_WINDOW.ago..)
                                         .includes(:user, :contact).order(:started_at).to_a
  end

  def live
    list = @user_id ? live_calls.select { |call| call.user_id == @user_id } : live_calls
    list.map do |call|
      { id: call.id, direction: call.direction, status: call.status, user: call.user&.name, customer: call.contact&.name,
        number: call.customer_number, started_at: call.started_at, answered_at: call.answered_at }
    end
  end

  # meta do mês (é mensal mesmo vendo hoje ou a semana) de um vendedor
  def goal
    return unless @user_id

    stats = Outsider::Voice::Stats.new(@access, Outsider::Crm::MonthlyConfig.current_month).to_h
    seller = stats[:sellers].find { |row| row[:id] == @user_id }
    seller && { calls: seller[:goal]['calls'], minutes: seller[:goal]['minutes'], month_calls: seller[:month][:outbound],
                month_minutes: (seller[:month][:talk_seconds] / 60.0).round, business_days: stats[:business_days],
                business_days_left: stats[:business_days_left] }
  end
end
