# OUTSIDER: painel (wallboard) da Telefonia (Entrega 23, refeito na 24). No período escolhido
# (Outsider::Voice::Period): os indicadores (Outsider::Voice::CallMetrics) com a comparação com o período
# anterior, ligações dia a dia (ou mês a mês), por hora e por dia da semana x hora, duração das conversas,
# tempo para atender, a equipe, quem está em ligação agora e a meta do mês.
#
# Gestor e administrador veem todos ou um vendedor; o vendedor vê só os próprios números. Datas e horas no
# fuso da telefonia (Telefonia > Configurações), o mesmo para todo mundo: antes vinha do navegador, e um
# computador em UTC jogava a ligação das 23h para o dia seguinte.
class Outsider::Voice::Wallboard
  # ligação sem fim avisado há mais que isso (central reiniciada no meio) não conta como em andamento
  LIVE_WINDOW = 4.hours
  SERIES = %i[inbound_answered missed outbound internal].freeze

  def initialize(access, period:, user_id: nil, from: nil, to: nil)
    @access = access
    @account = access.account_user.account
    @settings = Outsider::Voice::Settings.new(@account)
    @period = Outsider::Voice::Period.new(@settings.time_zone, period, from: from, to: to)
    @user_id = access.manager? ? user_id.presence&.to_i : access.account_user.user_id
  end

  attr_reader :period

  def to_h
    {
      period: @period.as_json, user_id: @user_id, manager: @access.manager?,
      summary: metrics.to_h, previous: Outsider::Voice::CallMetrics.new(previous_calls).to_h,
      talk_buckets: metrics.talk_buckets, wait_buckets: metrics.wait_buckets, service_seconds: Outsider::Voice::CallMetrics::SERVICE_SECONDS,
      by_hour: by_hour, timeline: timeline, by_weekday_hour: by_weekday_hour, to_return: to_return,
      agents: @access.manager? ? agents : [], live: live, goal: goal
    }
  end

  # as ligações do período (de quem está sendo visto), para as planilhas e o PDF
  def calls
    @calls ||= scope.where(started_at: @period.range).order(:started_at).to_a
  end

  def metrics
    @metrics ||= Outsider::Voice::CallMetrics.new(calls)
  end

  # dia a dia (ou mês a mês, em período longo): ligações de cada tipo, minutos e taxa de atendimento
  def timeline
    return if @period.single_day?

    groups = calls.group_by { |call| timeline_key(@period.local(call.started_at).to_date) }
    keys = @period.days.map { |day| timeline_key(day) }.uniq
    { unit: @period.daily? ? 'day' : 'month', rows: keys.map { |key| timeline_row(key, groups.fetch(key, [])) } }
  end

  # todos os vendedores no período, mesmo com um deles escolhido no painel
  def agents
    online = Outsider::Voice::CentralStatus.new(@account).to_h[:extensions]
    in_call = live_calls.filter_map(&:user_id)
    User.where(id: (@settings.enabled_agents.keys + calls_by_user.keys).uniq).order(:name).map do |user|
      extension = @settings.data['agents'].dig(user.id.to_s, 'extension')
      agent_row(user).merge(extension: extension, online: online.include?(extension), in_call: in_call.include?(user.id))
    end
  end

  def user
    @user_id && User.find_by(id: @user_id)
  end

  private

  def scope
    calls = Outsider::Voice::Call.where(account_id: @account.id)
    @user_id ? calls.where(user_id: @user_id) : calls
  end

  def previous_calls
    scope.where(started_at: @period.previous).to_a
  end

  def timeline_key(date)
    @period.daily? ? date : date.beginning_of_month
  end

  def timeline_row(date, list)
    metrics = Outsider::Voice::CallMetrics.new(list)
    counts = metrics.counts
    { date: date, future: @period.future?(date), talk_seconds: metrics.to_h[:talk_seconds], answer_rate: metrics.to_h[:answer_rate] }
      .merge(counts.slice(*SERIES)).merge(total: counts[:total])
  end

  def by_hour
    rows = Array.new(24) { |hour| SERIES.index_with(0).merge(hour: hour, talk_seconds: 0) }
    calls.each do |call|
      row = rows[@period.local(call.started_at).hour]
      row[series(call)] += 1
      row[:talk_seconds] += call.talk_seconds if call.answered?
    end
    rows
  end

  def series(call)
    return :internal if call.internal?
    return :outbound if call.outbound?

    call.answered? ? :inbound_answered : :missed
  end

  # [dia da semana (0 = domingo)][hora] = ligações
  def by_weekday_hour
    grid = Array.new(7) { Array.new(24, 0) }
    calls.each do |call|
      time = @period.local(call.started_at)
      grid[time.wday][time.hour] += 1
    end
    grid
  end

  # fila de retorno de agora (não só do período), do jeito que a pessoa vê em Ligações
  def to_return
    Outsider::Voice::CallAccess.new(@access, @settings).scope(Outsider::Voice::Call.where(account_id: @account.id).to_return).count
  end

  def calls_by_user
    @calls_by_user ||= Outsider::Voice::Call.where(account_id: @account.id, started_at: @period.range).where.not(user_id: nil).group_by(&:user_id)
  end

  def agent_row(user)
    metrics = Outsider::Voice::CallMetrics.new(calls_by_user.fetch(user.id, [])).to_h
    { id: user.id, name: user.name, thumbnail: user.avatar_url }.merge(
      metrics.slice(:total, :outbound, :outbound_answered, :contact_rate, :inbound_answered, :internal, :talk_seconds, :average_talk,
                    :customers)
    )
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

    month = Time.current.in_time_zone(@settings.time_zone).strftime('%Y-%m')
    stats = Outsider::Voice::Stats.new(@access, month).to_h
    seller = stats[:sellers].find { |row| row[:id] == @user_id }
    seller && { calls: seller[:goal]['calls'], minutes: seller[:goal]['minutes'], month_calls: seller[:month][:outbound],
                month_minutes: (seller[:month][:talk_seconds] / 60.0).round, business_days: stats[:business_days],
                business_days_left: stats[:business_days_left] }
  end
end
