# OUTSIDER: Agenda do Google no bloco Google (Outsider::Apps::Google::Calendar). Nada fica gravado no Chatwoot. Mesmas
# respostas da agenda da Microsoft (TeamsCalendarController), para a tela ser uma só.
#   GET    events         eventos entre from e to, no fuso da pessoa (time_zone)
#   POST   events         marcar (subject, start, end, all_day, online = Google Meet, attendees, body, location)
#   DELETE events/:id     cancelar (quem marcou) ou tirar da própria agenda (convidado)
#   GET    people         sugestões de convidados: os colegas do Chatwoot (com o Gmail de quem conectou o Google)
class Api::V1::Accounts::Outsider::Apps::GoogleCalendarController < Api::V1::Accounts::Outsider::Apps::BaseController
  MAX_PEOPLE = 300

  before_action { require_google(:calendar) }

  def index
    from = Time.zone.parse(params[:from].to_s) || Time.current.beginning_of_week
    to = Time.zone.parse(params[:to].to_s) || (from + 7.days)
    render json: { payload: calendar.events(from, to), time_zone: calendar.zone }
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def create
    subject = params[:subject].to_s.strip
    return render_error_code('invalid', :unprocessable_entity) if subject.blank? || params[:start].blank? || params[:end].blank?

    event = calendar.create(subject: subject, start: params[:start], finish: params[:end], all_day: cast(params[:all_day]) == true,
                            online: cast(params.fetch(:online, true)) == true, attendees: emails(params[:attendees]),
                            **place_fields)
    render json: event, status: :created
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def destroy
    calendar.delete(params[:id])
    head :no_content
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def people
    google = ::Outsider::GoogleLink.where(account_id: Current.account.id).where.not(email: [nil, '']).pluck(:user_id, :email).to_h
    list = Current.account.users.order(:name).limit(MAX_PEOPLE).flat_map do |user|
      next [] if user.id == Current.user.id

      [google[user.id], user.email].compact.uniq.map { |email| { name: user.name, email: email } }
    end
    render json: { payload: list }
  end

  private

  # OUTSIDER (Maps): o ponto exato escolhido no mapa vai no evento (coordenadas guardadas e o link do Maps na descrição)
  def place_fields
    place = ::Outsider::ContactPlaces.point(params[:place].respond_to?(:permit) ? params[:place].permit!.to_h : {})
    return { body: params[:body], location: params[:location] } unless place

    location = params[:location].presence || [place[:name], place[:address]].compact.uniq.join(' - ').presence
    link = "Local no Google Maps: #{::Outsider::Erp::OrderCalendars.maps_url(place)}"
    { body: [params[:body].presence, link].compact.join("\n\n"), location: location || "#{place[:latitude]}, #{place[:longitude]}",
      place: place }
  end

  def calendar
    @calendar ||= ::Outsider::Apps::Google::Calendar.new(google_link, params[:time_zone])
  end
end
