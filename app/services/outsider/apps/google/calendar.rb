# OUTSIDER: Agenda do Google no bloco Google (Aplicativos), a agenda principal da pessoa (permissão calendar.events).
# Nada fica gravado no Chatwoot: os eventos vêm do Google na hora, no fuso da pessoa.
# Mesmo formato da agenda da Microsoft (Api::V1::Accounts::Outsider::TeamsCalendarController#event_json): datas no fuso
# dela, sem o fuso no fim (2026-11-24T09:00:00); dia inteiro vai de 00:00 do dia até 00:00 do dia seguinte.
class Outsider::Apps::Google::Calendar
  MAX_RANGE = 62.days
  MAX_ATTENDEES = 50
  MAX_PAGES = 4
  RESPONSES = { 'accepted' => 'accepted', 'tentative' => 'tentativelyAccepted', 'declined' => 'declined',
                'needsAction' => 'notResponded' }.freeze

  def initialize(link, time_zone)
    @link = link
    @client = Outsider::Apps::Google::Client.new(link)
    @zone = ActiveSupport::TimeZone[time_zone.to_s] ? time_zone.to_s : 'America/Sao_Paulo'
  end

  attr_reader :zone

  def events(from, to)
    to = from + MAX_RANGE if to - from > MAX_RANGE
    query = { timeMin: from.utc.iso8601, timeMax: to.utc.iso8601, singleEvents: true, orderBy: 'startTime', maxResults: 250,
              timeZone: @zone }
    list = []
    MAX_PAGES.times do
      data = @client.get(events_url, query: query)
      list.concat(Array(data['items']))
      break if data['nextPageToken'].blank?

      query[:pageToken] = data['nextPageToken']
    end
    list.reject { |event| event['status'] == 'cancelled' }.map { |event| event_json(event) }
  end

  # online: reunião do Google Meet (o link vem no evento); attendees: e-mails convidados (o Google manda o convite)
  def create(subject:, start:, finish:, all_day: false, online: true, attendees: [], body: nil, location: nil)
    event = { summary: subject.to_s.first(250), description: body.to_s.first(4000).presence, location: location.to_s.first(250).presence,
              start: moment(start, all_day), end: moment(finish, all_day),
              attendees: Array(attendees).first(MAX_ATTENDEES).map { |email| { email: email } } }.compact
    if online && !all_day
      event[:conferenceData] = { createRequest: { requestId: SecureRandom.uuid, conferenceSolutionKey: { type: 'hangoutsMeet' } } }
    end
    event_json(@client.post(events_url, event, query: { conferenceDataVersion: 1, sendUpdates: 'all' }))
  end

  # quem marcou cancela para todos (o Google avisa os convidados); convidado só tira da própria agenda
  def delete(id)
    @client.delete("#{events_url}/#{Outsider::Apps::Google::Client.enc(id)}", query: { sendUpdates: 'all' })
    true
  end

  def event_json(event)
    me = Array(event['attendees']).find { |person| person['self'] }
    mine = event.dig('organizer', 'self') == true
    {
      id: event['id'], subject: event['summary'].to_s, start: local(event['start']), end: local(event['end']),
      all_day: event.dig('start', 'date').present?, online: join_url(event).present?, join_url: join_url(event),
      web_link: event['htmlLink'], location: event['location'].presence, cancelled: event['status'] == 'cancelled',
      organizer: event.dig('organizer', 'displayName').presence || event.dig('organizer', 'email'), mine: mine,
      response: mine ? 'organizer' : RESPONSES[me&.dig('responseStatus')], preview: plain(event['description']).first(300),
      attendees: Array(event['attendees']).reject { |person| person['resource'] }.first(MAX_ATTENDEES).map do |person|
        { name: person['displayName'].presence || person['email'], email: person['email'], response: RESPONSES[person['responseStatus']] }
      end
    }
  end

  private

  def events_url
    "#{Outsider::Apps::Google::Client::CALENDAR}/calendars/primary/events"
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

  # a descrição do Google pode vir em HTML
  def plain(text)
    Nokogiri::HTML(text.to_s.gsub(%r{<br\s*/?>}i, "\n")).text.to_s.squish
  end
end
