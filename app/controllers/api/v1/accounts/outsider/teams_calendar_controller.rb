# OUTSIDER: agenda da pessoa (Outlook/Teams) dentro da área Teams, com o Teams dela (permissão Calendars.ReadWrite,
# versão 2 das permissões). Nada fica gravado no Chatwoot: a Microsoft é sempre a fonte.
#   index: eventos entre from e to (calendarView), no fuso da pessoa.
#   create: marca um evento; online = reunião do Teams (vem o link para entrar); attendees = e-mails convidados.
#   destroy: cancela/apaga o evento (quem marcou cancela para todos; convidado só tira da própria agenda).
class Api::V1::Accounts::Outsider::TeamsCalendarController < Api::V1::Accounts::BaseController
  MAX_RANGE = 62.days
  MAX_ATTENDEES = 50

  before_action :require_link

  def index
    from = Time.zone.parse(params[:from].to_s) || Time.current.beginning_of_week
    to = Time.zone.parse(params[:to].to_s) || (from + 7.days)
    to = from + MAX_RANGE if to - from > MAX_RANGE
    query = { :startDateTime => from.utc.iso8601, :endDateTime => to.utc.iso8601, '$orderby' => 'start/dateTime', '$top' => 200,
              '$select' => 'id,subject,start,end,isAllDay,isOnlineMeeting,onlineMeeting,webLink,location,organizer,attendees,' \
                           'isCancelled,responseStatus,bodyPreview,isOrganizer' }
    data = client.get("/me/calendarView?#{query.to_query}", headers: { 'Prefer' => "outlook.timezone=\"#{time_zone}\"" })
    render json: { payload: Array(data['value']).map { |event| event_json(event) }, time_zone: time_zone }
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e, :bad_gateway)
  end

  def create
    subject = params[:subject].to_s.strip.first(250)
    return render_error_code('empty', :unprocessable_entity) if subject.blank? || params[:start].blank? || params[:end].blank?

    body = {
      subject: subject, isAllDay: cast(params[:all_day]),
      start: { dateTime: params[:start].to_s, timeZone: time_zone }, end: { dateTime: params[:end].to_s, timeZone: time_zone },
      body: { contentType: 'text', content: params[:body].to_s.first(4000) },
      attendees: attendees, isOnlineMeeting: cast(params.fetch(:online, true)), onlineMeetingProvider: 'teamsForBusiness'
    }
    body[:location] = { displayName: params[:location].to_s.first(250) } if params[:location].present?
    event = client.post('/me/events', body, headers: { 'Prefer' => "outlook.timezone=\"#{time_zone}\"" })
    render json: event_json(event), status: :created
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e, :bad_gateway)
  end

  def destroy
    client.delete("/me/events/#{::Outsider::Teams::Graph::Client.enc(params[:id])}")
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

    render_error_code('scope_outdated', :unprocessable_entity) if my_link.scope_version < ::Outsider::Teams::Graph::Login::SCOPE_VERSION
  end

  def client
    ::Outsider::Teams::Graph::Client.new(my_link)
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

  def event_json(event)
    {
      id: event['id'], subject: event['subject'], start: event.dig('start', 'dateTime'), end: event.dig('end', 'dateTime'),
      all_day: event['isAllDay'] == true, online: event['isOnlineMeeting'] == true, join_url: event.dig('onlineMeeting', 'joinUrl'),
      web_link: event['webLink'], location: event.dig('location', 'displayName').presence, cancelled: event['isCancelled'] == true,
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
