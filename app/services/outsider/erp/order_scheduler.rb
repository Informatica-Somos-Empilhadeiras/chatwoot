# OUTSIDER: agendar uma OS do ERP (aberta há tempo ou agora há pouco: a lista lê o ERP na hora) nas agendas conectadas
# de quem agenda (Outsider::Erp::OrderCalendars: Microsoft e/ou Google), com convidados por e-mail (o Google/Microsoft
# manda o convite) e, se quiser, um aviso por WhatsApp para até 5 contatos (Outsider::Erp::Delivery limita por hora).
# Também manda só um texto pelo WhatsApp sobre a OS (message). O evento mora na agenda da pessoa; aqui fica o resumo
# (Outsider::Erp::OrderSchedule) para o painel da OS mostrar e para cancelar. O técnico e o envio para o app do técnico
# também são escolhidos aqui (Outsider::Erp::Orders::Assignment), como no agendador do quadro de OS do Mais Prático.
# O local exato (place: um local do cliente, Outsider::ContactPlaces) vai no evento (endereço, coordenadas e o link do
# Google Maps) e, se pedir, como o pin do WhatsApp depois do aviso (Outsider::Erp::ScheduleLocationJob).
class Outsider::Erp::OrderScheduler
  include Outsider::Erp::Delivery

  MAX_ATTENDEES = 50
  MAX_TITLE = 250
  MAX_BODY = 4_000
  TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?\z/
  DATE = /\A\d{4}-\d{2}-\d{2}\z/
  WHATSAPP_TEXT = "Olá, {contato}! A Ordem de Serviço Nº {numero} foi agendada para {data} às {hora}.\nLocal: {local}".freeze
  MESSAGE_TEXT = 'Olá, {contato}! Sobre a Ordem de Serviço Nº {numero}: '.freeze
  # o pin vai alguns segundos depois do texto, para chegar depois dele no celular do cliente
  LOCATION_DELAY = 8.seconds

  def initialize(account_user, time_zone: nil)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
    @time_zone = time_zone
  end

  # o que a tela precisa: a OS, o evento sugerido, as agendas, quem convidar e os agendamentos que já existem
  def defaults(company, number, detail: nil)
    detail ||= Outsider::Erp::Records::Detail.new(@account, 'orders').build(company, number)
    contact = detail['contact_id'] && @account.contacts.find_by(id: detail['contact_id'])
    {
      order: order_info(detail), event: event_defaults(detail), calendars: calendars.available,
      suggestions: { emails: suggested_emails(detail, contact), whatsapp: [contact].compact.map { |item| contact_row(item) } },
      inboxes: recipients.whatsapp_inboxes.map { |inbox| { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type } },
      inbox_id: recipients.for_contact(contact)[:inbox_id], texts: { schedule: WHATSAPP_TEXT, message: MESSAGE_TEXT },
      limits: { whatsapp: MAX_WHATSAPP, attendees: MAX_ATTENDEES, whatsapp_per_hour: WHATSAPP_PER_HOUR },
      schedules: list(company, number), technicians: technicians, erp_write: Outsider::Erp::Settings.new(@account).write_enabled?,
      places: contact ? Outsider::ContactPlaces.new(contact).all.map(&:as_place_json) : []
    }
  end

  def list(company, number)
    Outsider::Erp::OrderSchedule.where(account_id: @account.id).for_order(company, number)
                                .includes(:user).order(:starts_at).map { |schedule| schedule_json(schedule) }
  end

  # params: title, start, end ("2026-11-25T09:00"), all_day, location, body, calendars [], attendees [],
  # place { name, address, latitude, longitude } + save_place (opcional),
  # whatsapp { contact_ids [], inbox_id, message, send_location } (opcional). => { schedule, results, whatsapp }
  def create(company, number, params)
    params = params.to_h.with_indifferent_access
    event = event_params(params)
    event[:place] = Outsider::ContactPlaces.point(params[:place]) if params[:place].present?
    providers = Array(params[:calendars]).map(&:to_s).uniq & Outsider::Erp::OrderCalendars::PROVIDERS
    raise Blocked, 'no_calendar' if providers.empty?
    raise Blocked, 'calendar_not_ready' unless providers.all? { |provider| calendars.ready?(provider) }

    notice = whatsapp_params(params[:whatsapp])
    notice[:place] = event[:place] if notice && event[:place] && truthy?(params.dig(:whatsapp, :send_location))
    results = providers.map { |provider| create_event(provider, event) }
    created = results.select { |row| row[:ok] }
    raise Blocked, "calendar_failed:#{results.first[:error]}" if created.empty?

    schedule = save(company, number, event, created)
    save_place(company, number, event[:place]) if event[:place] && truthy?(params[:save_place])
    assigned = Outsider::Erp::Orders::Assignment.new(@account, @user)
                                                .call(company, number, technician: params[:tecnico], app: truthy?(params[:enviar_app]))
    substatus = mark_scheduled(company, number)
    sent = notice ? send_notice(notice, schedule) : 0
    schedule.update!(whatsapp_count: sent) if sent.positive?
    { schedule: schedule_json(schedule), results: results, whatsapp: sent, substatus: substatus }.merge(assigned)
  end

  # só quem agendou cancela (o evento está na agenda dele); os convidados recebem o cancelamento do Google/Microsoft
  def cancel(schedule)
    raise Blocked, 'not_owner' unless schedule.user_id == @user.id

    schedule.events.each { |row| calendars.delete(row['provider'], row['id']) }
    schedule.destroy!
  end

  # só um texto pelo WhatsApp sobre a OS, para até MAX_WHATSAPP contatos
  def message(params)
    notice = whatsapp_params(params.to_h.with_indifferent_access) || raise(Blocked, 'no_phone')
    send_notice(notice, nil)
  end

  private

  def calendars
    @calendars ||= Outsider::Erp::OrderCalendars.new(@account, @user, @time_zone)
  end

  def recipients
    @recipients ||= Outsider::Erp::BudgetRecipients.new(@account_user)
  end

  def truthy?(value) = ActiveModel::Type::Boolean.new.cast(value) == true

  # os técnicos do cadastro do Mais Prático (a mesma lista do quadro de OS)
  def technicians
    Outsider::Erp::Lists.new(@account).technicians
  rescue Outsider::Erp::Client::Error
    []
  end

  def order_info(detail)
    header = detail['header'].to_h
    { company: detail['company'], number: detail['numero'], cliente: client_name(detail), atendimento: header['atendimento'],
      tecnico: header['tecnico_nome'], tecnico_codigo: header['tecnico'].to_i, equipamento: header['equipamento'],
      previsao: header['previsao'], status: header['status'], contact_id: detail['contact_id'] }
  end

  def client_name(detail)
    detail['cliente'].to_h['nome'].presence || detail['header'].to_h['cliente_nome']
  end

  def event_defaults(detail)
    header = detail['header'].to_h
    title = ["OS #{detail['numero']}", client_name(detail), header['atendimento']].compact_blank.join(' · ')
    { title: title.first(MAX_TITLE), location: address(detail['cliente'].to_h), body: description(detail),
      date: header['previsao'].to_s.first(10).presence&.then { |value| value.match?(DATE) ? value : nil } }
  end

  def address(client)
    street = [client['endereco'], client['numero']].compact_blank.join(', ')
    city = [client['cidade'], client['uf']].compact_blank.join(' - ')
    [street, client['complemento'], client['bairro'], city].compact_blank.join(', ').first(250)
  end

  def description(detail)
    header = detail['header'].to_h
    lines = [
      "Ordem de Serviço Nº #{detail['numero']}",
      ("Cliente: #{client_name(detail)}" if client_name(detail).present?),
      ("Tipo de atendimento: #{header['atendimento']}" if header['atendimento'].present?),
      ("Equipamento: #{header['equipamento']}" if header['equipamento'].present?),
      ("Série: #{header['serie']}" if header['serie'].present?),
      ("Técnico: #{header['tecnico_nome']}" if header['tecnico_nome'].present?),
      ("Defeitos: #{header['defeitos']}" if header['defeitos'].present?),
      ("No Chatwoot: #{order_link(detail)}" if Outsider::Teams::Graph::Login.site.present?)
    ]
    lines.compact.join("\n").first(MAX_BODY)
  end

  def order_link(detail)
    "#{Outsider::Teams::Graph::Login.site}/app/accounts/#{@account.id}/erp/os?open=#{detail['company']}:#{detail['numero']}"
  end

  # o contato do Chatwoot ligado ao cliente, os e-mails do cadastro do cliente no ERP e o técnico da OS (o colega com
  # esse código do ERP em Configurações do ERP, pelo e-mail da agenda dele quando conectou)
  def suggested_emails(detail, contact)
    list = []
    list << { email: contact.email, name: contact.name, kind: 'contact' } if contact&.email.present?
    Outsider::Erp::CustomerRecord.emails(detail['cliente'].to_h).each do |email|
      list << { email: email, name: client_name(detail), kind: 'client' }
    end
    list.concat(technician_emails(detail['header'].to_h))
    list.uniq { |row| row[:email].downcase }
  end

  def technician_emails(header)
    code = header['tecnico'].to_s
    return [] unless code.to_i.positive?

    user_id = Outsider::Erp::Settings.new(@account).data['user_erp_ids'].to_h.key(code)
    user = user_id && @account.users.find_by(id: user_id)
    return [] unless user

    calendar = Outsider::GoogleLink.find_by(account_id: @account.id, user_id: user.id)&.email ||
               Outsider::TeamsLink.find_by(account_id: @account.id, user_id: user.id)&.email
    [{ email: calendar.presence || user.email, name: user.name, kind: 'technician' }]
  end

  def contact_row(contact)
    Outsider::Crm::Serializer.contact(contact)
  end

  def event_params(params)
    all_day = ActiveModel::Type::Boolean.new.cast(params[:all_day]) == true
    start = params[:start].to_s.strip
    finish = params[:end].to_s.strip
    raise Blocked, 'invalid_time' unless start.match?(TIME) && finish.match?(TIME)

    start = "#{start.first(16)}:00"
    finish = "#{finish.first(16)}:00"
    finish = "#{(Date.parse(finish.first(10)) + 1).iso8601}T00:00:00" if all_day && finish.first(10) <= start.first(10)
    raise Blocked, 'invalid_time' if !all_day && finish <= start

    title = params[:title].to_s.squish.first(MAX_TITLE)
    raise Blocked, 'title_required' if title.blank?

    { subject: title, start: start, finish: finish, all_day: all_day, body: params[:body].to_s.first(MAX_BODY),
      location: params[:location].to_s.squish.first(250).presence, attendees: attendees(params[:attendees]) }
  end

  def attendees(value)
    list = Array(value).flat_map { |item| item.to_s.split(/[;,\s]+/) }.compact_blank.uniq(&:downcase)
    raise Blocked, 'too_many_attendees' if list.size > MAX_ATTENDEES
    raise Blocked, 'invalid_email' unless list.all?(URI::MailTo::EMAIL_REGEXP)

    list
  end

  # confere tudo do aviso antes de marcar o evento (para não marcar e depois falhar no WhatsApp por dado errado)
  def whatsapp_params(value)
    value = value.to_h.with_indifferent_access
    return nil if Array(value[:contact_ids]).compact_blank.empty?

    contacts = whatsapp_contacts!(value)
    inbox = whatsapp_inbox(value[:inbox_id])
    text = clean(value[:message], MAX_MESSAGE)
    raise Blocked, 'message_required' if text.blank?

    { contacts: contacts, inbox: inbox, text: text }
  end

  def create_event(provider, event)
    { provider: provider, ok: true }.merge(calendars.create(provider, with_place(event)))
  rescue Outsider::Erp::OrderCalendars::Error => e
    Rails.logger.info("[Outsider::Erp] agendar OS (#{provider}): #{e.message}")
    { provider: provider, ok: false, error: e.is_a?(Outsider::Teams::Graph::Client::Reconnect) ? 'reconnect' : e.message.to_s.first(200) }
  end

  # o evento com o local exato: o endereço no local (ou as coordenadas, sem texto) e o link do Maps na descrição
  def with_place(event)
    place = event[:place]
    return event unless place

    link = "Local no Google Maps: #{Outsider::Erp::OrderCalendars.maps_url(place)}"
    location = event[:location].presence || [place[:name], place[:address]].compact.uniq.join(' - ').presence ||
               "#{place[:latitude]}, #{place[:longitude]}"
    event.merge(location: location.first(250), body: [event[:body].presence, link].compact.join("\n\n").first(MAX_BODY))
  end

  # guarda o local no cliente (contato do Chatwoot ligado à OS) para a próxima vez
  def save_place(company, number, place)
    detail = Outsider::Erp::Records::Detail.new(@account, 'orders').build(company, number)
    contact = detail['contact_id'] && @account.contacts.find_by(id: detail['contact_id'])
    Outsider::ContactPlaces.new(contact, @user).create(place.merge(name: place[:name] || place[:address])) if contact
  rescue StandardError => e # o evento já está marcado: guardar o local nunca derruba o agendamento
    Rails.logger.info("[Outsider::Erp] local do agendamento não guardado no cliente: #{e.class} #{e.message}")
  end

  def save(company, number, event, created)
    zone = ActiveSupport::TimeZone[calendars.zone]
    place = event[:place].to_h
    Outsider::Erp::OrderSchedule.create!(
      account: @account, user: @user, company: company, order_number: number, title: event[:subject],
      starts_at: zone.parse(event[:start]), ends_at: zone.parse(event[:finish]), all_day: event[:all_day], time_zone: calendars.zone,
      location: with_place(event)[:location], attendees: event[:attendees],
      place_name: place[:name] || place[:address], latitude: place[:latitude], longitude: place[:longitude],
      events: created.map { |row| { 'provider' => row[:provider], 'id' => row[:id], 'web_link' => row[:web_link] } }
    )
  end

  # OS agendada vai para o substatus "AGENDADO" da filial dela (ex.: "2-AGENDADO (DF)"), com o histórico do ERP como no
  # painel deles (Outsider::Erp::Writer). Sem a escrita ligada ou sem esse substatus, o agendamento vale do mesmo jeito.
  def mark_scheduled(company, number)
    return { ok: false, reason: 'write_disabled' } unless Outsider::Erp::Settings.new(@account).write_enabled?

    writer = Outsider::Erp::Writer.new(account: @account, user: @user)
    value = writer.substatus_choices(company).find { |option| scheduled_substatus?(option) }
    return { ok: false, reason: 'no_substatus' } unless value

    order = writer.substatus(company: company, code: number, value: value)
    { ok: true, value: order['SubStatus'] }
  rescue Outsider::Erp::Writer::Disabled
    { ok: false, reason: 'write_disabled' }
  rescue StandardError => e # o evento já está na agenda: o substatus nunca derruba o agendamento
    Rails.logger.info("[Outsider::Erp] OS agendada sem trocar o substatus: #{e.class} #{e.message}")
    { ok: false, reason: 'substatus_failed' }
  end

  def scheduled_substatus?(value)
    Outsider::Erp::ServiceOrders.normalize(value.to_s.sub(/\s*\([A-Za-z]{2}\)\s*\z/, '').sub(/\A\s*\d+\s*-\s*/, '')) == 'AGENDADO'
  end

  def send_notice(notice, _schedule)
    whatsapp_quota!(notice[:contacts].size)
    notice[:contacts].each do |contact|
      conversation = whatsapp_conversation(notice[:inbox], contact)
      post(conversation, personalize(notice[:text], contact))
      send_location_later(conversation, notice[:place]) if notice[:place]
    end
    notice[:contacts].size
  end

  def send_location_later(conversation, place)
    return unless Outsider::EvolutionApi.evolution_inbox?(conversation.inbox)

    Outsider::Erp::ScheduleLocationJob.set(wait: LOCATION_DELAY).perform_later(conversation.id, @user.id, place.stringify_keys)
  end

  def schedule_json(schedule)
    {
      id: schedule.id, title: schedule.title, start: local(schedule, schedule.starts_at), end: local(schedule, schedule.ends_at),
      all_day: schedule.all_day, location: schedule.location, attendees: schedule.attendees, whatsapp_count: schedule.whatsapp_count,
      calendars: schedule.events.map { |row| row.slice('provider', 'web_link') }, user: schedule.user&.name,
      mine: schedule.user_id == @user.id, created_at: schedule.created_at.iso8601,
      place: schedule.latitude && { name: schedule.place_name, latitude: schedule.latitude.to_f, longitude: schedule.longitude.to_f }
    }
  end

  def local(schedule, time)
    zone = ActiveSupport::TimeZone[schedule.time_zone.to_s] || ActiveSupport::TimeZone['America/Sao_Paulo']
    time.in_time_zone(zone).strftime('%Y-%m-%dT%H:%M:%S')
  end
end
