# OUTSIDER: Agenda do Google no bloco Google (Aplicativos): a agenda principal da pessoa e as outras que ela vê na conta
# Google (as dela e as compartilhadas com ela, permissão calendar.calendarlist.readonly para a lista; calendar.events
# para ler e marcar). calendar_id 'primary' = a principal. Nada fica gravado no Chatwoot: os eventos vêm do Google na
# hora, no fuso da pessoa.
# Mesmo formato da agenda da Microsoft (Api::V1::Accounts::Outsider::TeamsCalendarController#event_json): datas no fuso
# dela, sem o fuso no fim (2026-11-24T09:00:00); dia inteiro vai de 00:00 do dia até 00:00 do dia seguinte.
class Outsider::Apps::Google::Calendar
  MAX_RANGE = 62.days
  MAX_ATTENDEES = 50
  MAX_PAGES = 4
  RESPONSES = { 'accepted' => 'accepted', 'tentative' => 'tentativelyAccepted', 'declined' => 'declined',
                'needsAction' => 'notResponded' }.freeze
  EDIT_ROLES = %w[writer owner].freeze

  def initialize(link, time_zone)
    @link = link
    @client = Outsider::Apps::Google::Client.new(link)
    @zone = ActiveSupport::TimeZone[time_zone.to_s] ? time_zone.to_s : 'America/Sao_Paulo'
  end

  attr_reader :zone

  # [{ id, name, color, primary, can_edit }]: sem a permissão da lista (entrou antes dela), só a principal
  def calendars
    return [primary_calendar] unless @link.allows?(:calendars)

    data = @client.get("#{Outsider::Apps::Google::Client::CALENDAR}/users/me/calendarList", query: { maxResults: 100 })
    list = Array(data['items']).reject { |item| item['hidden'] || item['deleted'] }.map do |item|
      { id: item['primary'] ? 'primary' : item['id'], name: item['summaryOverride'].presence || item['summary'].to_s,
        color: item['backgroundColor'], primary: item['primary'] == true, can_edit: EDIT_ROLES.include?(item['accessRole']) }
    end
    list.sort_by { |item| [item[:primary] ? 0 : 1, item[:can_edit] ? 0 : 1, item[:name].downcase] }
  end

  def events(from, to, calendar_id: 'primary')
    to = from + MAX_RANGE if to - from > MAX_RANGE
    query = { timeMin: from.utc.iso8601, timeMax: to.utc.iso8601, singleEvents: true, orderBy: 'startTime', maxResults: 250,
              timeZone: @zone }
    list = []
    MAX_PAGES.times do
      data = @client.get(events_url(calendar_id), query: query)
      list.concat(Array(data['items']))
      break if data['nextPageToken'].blank?

      query[:pageToken] = data['nextPageToken']
    end
    list.reject { |event| event['status'] == 'cancelled' }.map { |event| event_json(event) }
  end

  # online: reunião do Google Meet (o link vem no evento); attendees: e-mails convidados (o Google manda o convite)
  # place: { latitude, longitude } (opcional): o ponto exato fica guardado no evento para o Chatwoot mostrar o Street View
  def create(subject:, start:, finish:, all_day: false, online: true, attendees: [], body: nil, location: nil, place: nil, # rubocop:disable Metrics/ParameterLists
             calendar_id: 'primary')
    event = { summary: subject.to_s.first(250), description: body.to_s.first(4000).presence, location: location.to_s.first(250).presence,
              start: moment(start, all_day), end: moment(finish, all_day),
              attendees: Array(attendees).first(MAX_ATTENDEES).map { |email| { email: email } } }.compact
    event[:extendedProperties] = { private: { outsider_latitude: place[:latitude].to_s, outsider_longitude: place[:longitude].to_s } } if place
    if online && !all_day
      event[:conferenceData] = { createRequest: { requestId: SecureRandom.uuid, conferenceSolutionKey: { type: 'hangoutsMeet' } } }
    end
    event_json(@client.post(events_url(calendar_id), event, query: { conferenceDataVersion: 1, sendUpdates: 'all' }))
  end

  # quem marcou cancela para todos (o Google avisa os convidados); convidado só tira da própria agenda
  def delete(id, calendar_id: 'primary')
    @client.delete("#{events_url(calendar_id)}/#{Outsider::Apps::Google::Client.enc(id)}", query: { sendUpdates: 'all' })
    true
  end

  def event_json(event)
    me = Array(event['attendees']).find { |person| person['self'] }
    mine = event.dig('organizer', 'self') == true
    {
      id: event['id'], subject: event['summary'].to_s, start: local(event['start']), end: local(event['end']),
      all_day: event.dig('start', 'date').present?, online: join_url(event).present?, join_url: join_url(event),
      web_link: event['htmlLink'], location: event['location'].presence, cancelled: event['status'] == 'cancelled', **point(event),
      organizer: event.dig('organizer', 'displayName').presence || event.dig('organizer', 'email'), mine: mine,
      response: mine ? 'organizer' : RESPONSES[me&.dig('responseStatus')], preview: plain(event['description']).first(300),
      attendees: Array(event['attendees']).reject { |person| person['resource'] }.first(MAX_ATTENDEES).map do |person|
        { name: person['displayName'].presence || person['email'], email: person['email'], response: RESPONSES[person['responseStatus']] }
      end
    }
  end

  private

  def events_url(calendar_id)
    "#{Outsider::Apps::Google::Client::CALENDAR}/calendars/#{Outsider::Apps::Google::Client.enc(calendar_id.presence || 'primary')}/events"
  end

  def primary_calendar
    { id: 'primary', name: @link.email.to_s, color: nil, primary: true, can_edit: true }
  end

  # "2026-11-24T09:00:00" no fuso da pessoa; dia inteiro só com a data
  def moment(value, all_day)
    return { date: value.to_s.first(10) } if all_day

    { dateTime: value.to_s.first(19), timeZone: @zone }
  end

  def local(value)
    return "#{value['date']}T00:00:00" if value.is_a?(Hash) && value['date'].present?
    return nil unless value.is_a?(Hash) && value['dateTime'].present?

    Time.zone.parse(value['dateTime']).in_time_zone(@zone).strftime('%Y-%m-%dT%H:%M:%S')
  rescue ArgumentError
    value['dateTime'].to_s.first(19)
  end

  def join_url(event)
    event['hangoutLink'].presence ||
      Array(event.dig('conferenceData', 'entryPoints')).find { |point| point['entryPointType'] == 'video' }&.dig('uri')
  end

  # o ponto exato guardado pelo Chatwoot no evento (latitude/longitude nil quando não tem)
  def point(event)
    data = event.dig('extendedProperties', 'private').to_h
    latitude = Float(data['outsider_latitude'].to_s, exception: false)
    longitude = Float(data['outsider_longitude'].to_s, exception: false)
    latitude && longitude ? { latitude: latitude, longitude: longitude } : { latitude: nil, longitude: nil }
  end

  # a descrição do Google pode vir em HTML
  def plain(text)
    Nokogiri::HTML(text.to_s.gsub(%r{<br\s*/?>}i, "\n")).text.to_s.squish
  end
end
