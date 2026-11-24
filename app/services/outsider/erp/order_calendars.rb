# OUTSIDER: as agendas conectadas de quem está agendando uma OS (Outsider::Erp::OrderScheduler): a da Microsoft (o Teams
# da pessoa, permissão de agenda) e a do Google (Aplicativos > Google). Cada uma com o login da própria pessoa; o evento
# fica na agenda dela e os convidados recebem o convite do próprio Google/Microsoft.
class Outsider::Erp::OrderCalendars
  PROVIDERS = %w[microsoft google].freeze
  Error = Outsider::Teams::Graph::Client::Error

  def initialize(account, user, time_zone)
    @account = account
    @user = user
    @zone = ActiveSupport::TimeZone[time_zone.to_s] ? time_zone.to_s : 'America/Sao_Paulo'
  end

  attr_reader :zone

  # [{ provider, ready, email, reason }]; reason: not_connected | reconnect | scope_outdated
  def available
    [state('microsoft', microsoft_link, microsoft_link && Outsider::Teams::Graph::Login.allows?(microsoft_link, :calendar)),
     state('google', google_link, google_link&.status == 'active' && google_link.allows?(:calendar))]
  end

  def ready?(provider)
    available.find { |item| item[:provider] == provider.to_s }&.dig(:ready) == true
  end

  # event: { subject, start, finish ("2026-11-25T09:00:00", no fuso da pessoa), all_day, attendees, body, location }
  # => { provider, id, web_link }
  def create(provider, event)
    case provider.to_s
    when 'microsoft' then create_microsoft(event)
    when 'google' then create_google(event)
    else raise ArgumentError, 'provider'
    end
  end

  # cancela o evento (o Google e a Microsoft avisam os convidados); já apagado na agenda conta como cancelado
  def delete(provider, id)
    case provider.to_s
    when 'microsoft' then microsoft_client.delete("/me/events/#{Outsider::Teams::Graph::Client.enc(id)}")
    when 'google' then Outsider::Apps::Google::Calendar.new(google_link, @zone).delete(id)
    end
    true
  rescue Error => e
    raise unless e.status.to_i == 404 || e.status.to_i == 410

    true
  end

  private

  def state(provider, link, ready)
    reason = if link.nil? then 'not_connected'
             elsif link.status != 'active' then 'reconnect'
             elsif !ready then 'scope_outdated'
             end
    { provider: provider, ready: ready == true, email: link&.email, reason: reason }
  end

  def microsoft_link
    @microsoft_link ||= Outsider::TeamsLink.find_by(account_id: @account.id, user_id: @user.id)
  end

  def google_link
    @google_link ||= Outsider::GoogleLink.find_by(account_id: @account.id, user_id: @user.id)
  end

  def microsoft_client
    raise Error.new('not_connected', 422) unless ready?('microsoft')

    Outsider::Teams::Graph::Client.new(microsoft_link)
  end

  def create_microsoft(event)
    body = {
      subject: event[:subject], isAllDay: event[:all_day] == true,
      start: { dateTime: microsoft_time(event[:start], event[:all_day]), timeZone: @zone },
      end: { dateTime: microsoft_time(event[:finish], event[:all_day]), timeZone: @zone },
      body: { contentType: 'text', content: event[:body].to_s }, isOnlineMeeting: false,
      attendees: Array(event[:attendees]).map { |email| { emailAddress: { address: email }, type: 'required' } }
    }
    body[:location] = { displayName: event[:location] } if event[:location].present?
    data = microsoft_client.post('/me/events', body, headers: { 'Prefer' => "outlook.timezone=\"#{@zone}\"" })
    { provider: 'microsoft', id: data['id'], web_link: data['webLink'] }
  end

  # a Microsoft quer o dia inteiro de 00:00 a 00:00 do dia seguinte
  def microsoft_time(value, all_day)
    all_day ? "#{value.to_s.first(10)}T00:00:00" : value.to_s.first(19)
  end

  def create_google(event)
    raise Error.new('not_connected', 422) unless ready?('google')

    data = Outsider::Apps::Google::Calendar.new(google_link, @zone).create(
      subject: event[:subject], start: event[:start], finish: event[:finish], all_day: event[:all_day] == true, online: false,
      attendees: event[:attendees], body: event[:body], location: event[:location]
    )
    { provider: 'google', id: data[:id], web_link: data[:web_link] }
  end
end
