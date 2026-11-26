# OUTSIDER: agenda da pessoa (Outlook/Teams) dentro da área Teams, com o Teams dela (permissão Calendars.ReadWrite,
# versão 2 das permissões). Nada fica gravado no Chatwoot: a Microsoft é sempre a fonte.
#   calendars: as agendas da pessoa e as que outras pessoas compartilharam com ela (permissões versão 5 para as
#              compartilhadas; antes disso, só as dela). 'primary' = a agenda padrão.
#   index: eventos entre from e to (calendarView), no fuso da pessoa, das agendas calendar_ids[] (até 10).
#   create: marca um evento (calendar_id); online = reunião do Teams (vem o link para entrar); attendees = e-mails.
#   destroy: cancela/apaga o evento (quem marcou cancela para todos; convidado só tira da própria agenda).
class Api::V1::Accounts::Outsider::TeamsCalendarController < Api::V1::Accounts::BaseController
  MAX_RANGE = 62.days
  MAX_ATTENDEES = 50
  MAX_CALENDARS = 10

  before_action :require_link

  def index
    from = Time.zone.parse(params[:from].to_s) || Time.current.beginning_of_week
    to = Time.zone.parse(params[:to].to_s) || (from + 7.days)
    to = from + MAX_RANGE if to - from > MAX_RANGE
    query = { :startDateTime => from.utc.iso8601, :endDateTime => to.utc.iso8601, '$orderby' => 'start/dateTime', '$top' => 200,
              '$select' => 'id,subject,start,end,isAllDay,isOnlineMeeting,onlineMeeting,webLink,location,organizer,attendees,' \
                           'isCancelled,responseStatus,bodyPreview,isOrganizer' }
    payload = calendar_ids.flat_map do |id|
      data = client.get("#{calendar_path(id)}/calendarView?#{query.to_query}", headers: { 'Prefer' => "outlook.timezone=\"#{time_zone}\"" })
      Array(data['value']).map { |event| event_json(event).merge(calendar_id: id) }
    end
    render json: { payload: payload, time_zone: time_zone }
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e, :bad_gateway)
  end

  def calendars
    data = client.get('/me/calendars?$top=50&$select=id,name,hexColor,canEdit,isDefaultCalendar')
    list = Array(data['value']).map do |item|
      { id: item['isDefaultCalendar'] ? 'primary' : item['id'], name: item['name'].to_s, color: item['hexColor'].presence,
        primary: item['isDefaultCalendar'] == true, can_edit: item['canEdit'] == true }
    end
    list = list.select { |item| item[:primary] } unless shared_allowed?
    render json: { payload: list.sort_by { |item| [item[:primary] ? 0 : 1, item[:name].downcase] }, complete: shared_allowed? }
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e, :bad_gateway)
  end

  def create
    subject = params[:subject].to_s.strip.first(250)
    return render_error_code('empty', :unprocessable_entity) if subject.blank? || params[:start].blank? || params[:end].blank?

    body = {
      subject: subject, isAllDay: cast(params[:all_day]),
      start: { dateTime: params[:start].to_s, timeZone: time_zone }, end: { dateTime: params[:end].to_s, timeZone: time_zone },
      body: { contentType: 'text', content: body_with_place(params[:body].to_s).first(4000) },
      attendees: attendees, isOnlineMeeting: cast(params.fetch(:online, true)), onlineMeetingProvider: 'teamsForBusiness'
    }
    body[:location] = location_with_place(params[:location].to_s.first(250)) if params[:location].present? || place
    calendar_id = params[:calendar_id].presence || 'primary'
    event = client.post("#{calendar_path(calendar_id)}/events", body, headers: { 'Prefer' => "outlook.timezone=\"#{time_zone}\"" })
    render json: event_json(event).merge(calendar_id: calendar_id), status: :created
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e, :bad_gateway)
  end

  def destroy
    client.delete("#{calendar_path(params[:calendar_id].presence || 'primary')}/events/#{::Outsider::Teams::Graph::Client.enc(params[:id])}")
    head :no_content
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e, :bad_gateway)
  end

  private

  def my_link
    @my_link ||= ::Outsider::TeamsLink.find_by(account_id: Current.account.id, user_id: Current.user.id)
  end

  def require_link
    return render_error_code('not_connected', :unprocessable_entity) unless my_link&.status == 'active'

    render_error_code('scope_outdated', :unprocessable_entity) unless ::Outsider::Teams::Graph::Login.allows?(my_link, :calendar)
  end

  def client
    ::Outsider::Teams::Graph::Client.new(my_link)
  end

  def shared_allowed? = ::Outsider::Teams::Graph::Login.allows?(my_link, :shared_calendars)

  def calendar_ids
    ids = Array(params[:calendar_ids]).map(&:to_s).compact_blank.uniq.first(MAX_CALENDARS)
    ids = ids.select { |id| id == 'primary' } unless shared_allowed?
    ids.presence || ['primary']
  end

  # 'primary' = a agenda padrão da pessoa
  def calendar_path(id)
    id == 'primary' ? '/me/calendar' : "/me/calendars/#{::Outsider::Teams::Graph::Client.enc(id)}"
  end

  def cast(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  # fuso da pessoa (vem do navegador); inválido vira o do Brasil
  def time_zone
    @time_zone ||= begin
      zone = params[:time_zone].to_s
      ActiveSupport::TimeZone[zone] ? zone : 'America/Sao_Paulo'
    end
  end

  def attendees
    Array(params[:attendees]).map(&:to_s).map(&:strip).grep(URI::MailTo::EMAIL_REGEXP).uniq.first(MAX_ATTENDEES)
                             .map { |email| { emailAddress: { address: email }, type: 'required' } }
  end

  # OUTSIDER (Maps): o ponto exato escolhido no mapa (place: name, address, latitude, longitude)
  def place
    @place ||= ::Outsider::ContactPlaces.point(params[:place].respond_to?(:permit) ? params[:place].permit!.to_h : {})
  end

  def body_with_place(text)
    return text unless place

    [text.presence, "Local no Google Maps: #{::Outsider::Erp::OrderCalendars.maps_url(place)}"].compact.join("\n\n")
  end

  def location_with_place(text)
    return { displayName: text } unless place

    name = text.presence || [place[:name], place[:address]].compact.uniq.join(' - ').presence || "#{place[:latitude]}, #{place[:longitude]}"
    { displayName: name.first(250), coordinates: { latitude: place[:latitude], longitude: place[:longitude] } }
  end

  def event_json(event)
    {
      id: event['id'], subject: event['subject'], start: event.dig('start', 'dateTime'), end: event.dig('end', 'dateTime'),
      all_day: event['isAllDay'] == true, online: event['isOnlineMeeting'] == true, join_url: event.dig('onlineMeeting', 'joinUrl'),
      web_link: event['webLink'], location: event.dig('location', 'displayName').presence, cancelled: event['isCancelled'] == true,
      latitude: event.dig('location', 'coordinates', 'latitude'), longitude: event.dig('location', 'coordinates', 'longitude'),
      organizer: event.dig('organizer', 'emailAddress', 'name'), mine: event['isOrganizer'] == true,
      response: event.dig('responseStatus', 'response'), preview: event['bodyPreview'].to_s.first(300),
      attendees: Array(event['attendees']).first(MAX_ATTENDEES).map do |person|
        { name: person.dig('emailAddress', 'name'), email: person.dig('emailAddress', 'address'), response: person.dig('status', 'response') }
      end
    }
  end

  def render_error(error, status)
    render json: { error: 'graph', message: error.message.to_s.first(300) }, status: status
  end

  def render_error_code(code, status)
    render json: { error: code, message: code }, status: status
  end
end
