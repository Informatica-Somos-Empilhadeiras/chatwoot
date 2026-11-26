require 'rails_helper'

# OUTSIDER: agendar OS do ERP nas agendas conectadas (Microsoft e Google) de quem agenda, com convidados por e-mail e
# aviso por WhatsApp para até 5 contatos (com limite por hora); e o envio do relatório para vários contatos.
RSpec.describe 'Outsider ERP order schedules', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Ana Agenda') }
  let(:technician) { create(:user, account: account, role: :agent, name: 'Téo Técnico', email: 'teo@empresa.com') }
  let(:inbox) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/somos').inbox }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/erp/service_orders" }
  let(:marcos) { create(:contact, account: account, name: 'MARCOS pereira', email: 'marcos@rota.com.br', phone_number: '+5562999990001') }
  let(:julia) { create(:contact, account: account, name: 'Júlia Lima', phone_number: '+5562999990002') }
  let(:all_scopes) { (%w[openid email profile] + Outsider::GoogleLink::FEATURES.values).join(' ') }
  let(:detail) do
    {
      'kind' => 'orders', 'company' => 'somosemp', 'numero' => 850, 'contact_id' => marcos.id,
      'header' => { 'atendimento' => 'PREVENTIVA', 'tecnico' => 12, 'tecnico_nome' => 'Téo', 'previsao' => '2026-11-26 00:00:00',
                    'equipamento' => 'Empilhadeira 2,5 t', 'defeitos' => 'Vazamento', 'status' => 'NEGOCIAÇÃO' },
      'cliente' => { 'nome' => 'Transportes Rota', 'endereco' => 'Rua A', 'numero' => '10', 'bairro' => 'Centro', 'cidade' => 'Goiânia',
                     'uf' => 'GO', 'email' => 'compras@rota.com.br; marcos@rota.com.br' }
    }
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    settings.update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc123', 'user_erp_ids' => { technician.id.to_s => '12' })
    allow_any_instance_of(Outsider::Erp::Records::Detail).to receive(:build).and_return(detail) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Erp::Lists).to receive(:technicians).and_return([]) # rubocop:disable RSpec/AnyInstance
    Outsider::GoogleLink.create!(account: account, user: agent, google_user_id: 'g-1', email: 'ana@gmail.com', display_name: 'Ana',
                                 access_token: 'token-g', refresh_token: 'refresh-g', token_expires_at: 1.hour.from_now, scopes: all_scopes)
    Outsider::GoogleLink.create!(account: account, user: technician, google_user_id: 'g-2', email: 'teo@gmail.com', display_name: 'Teo',
                                 access_token: 'token-t', refresh_token: 'refresh-t', token_expires_at: 1.hour.from_now, scopes: all_scopes)
    Redis::Alfred.delete("outsider:erp:whatsapp:#{account.id}:#{agent.id}:#{Time.current.strftime('%Y%m%d%H')}")
  end

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chat.exemplo.com.br') { example.run }
  end

  def call(verb, path, params = {})
    send(verb, "#{base}/#{path}", params: params, headers: agent.create_new_auth_token, as: :json)
    response.parsed_body
  end

  it 'suggests the event, the calendars and who to invite (contact, client e-mails and the technician by his calendar)' do
    body = call(:get, 'schedule', company: 'somosemp', code: 850, time_zone: 'America/Sao_Paulo')
    # o local fica vazio: o endereço do cadastro muitas vezes não é onde a máquina está (vai o ponto escolhido no mapa)
    expect(body['event']).to include('title' => 'OS 850 · Transportes Rota · PREVENTIVA', 'date' => '2026-11-26', 'location' => nil)
    expect(body['event']['body']).to include('Equipamento: Empilhadeira 2,5 t', 'Defeitos: Vazamento', 'https://chat.exemplo.com.br/app/accounts/')
    expect(body['calendars']).to contain_exactly(include('provider' => 'microsoft', 'ready' => false, 'reason' => 'not_connected'),
                                                 include('provider' => 'google', 'ready' => true, 'email' => 'ana@gmail.com'))
    expect(body['suggestions']['emails'].map { |row| row.values_at('email', 'kind') })
      .to eq([%w[marcos@rota.com.br contact], %w[compras@rota.com.br client], %w[teo@gmail.com technician]])
    expect(body['suggestions']['whatsapp'].pluck('id')).to eq([marcos.id])
    expect(body['inboxes'].pluck('id')).to eq([inbox.id])
  end

  it 'books the OS in Google with the guests, warns two contacts on WhatsApp by first name and lists/cancels it' do # rubocop:disable RSpec/MultipleExpectations
    created = stub_request(:post, 'https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1&sendUpdates=all')
              .with { |request| JSON.parse(request.body).values_at('summary', 'location') == ['OS 850', 'Rua A'] }
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                         body: { id: 'ev1', summary: 'OS 850', htmlLink: 'https://calendar.google.com/ev1', status: 'confirmed',
                                 start: { dateTime: '2026-11-26T09:00:00-03:00' }, end: { dateTime: '2026-11-26T11:00:00-03:00' } }.to_json)
    body = call(:post, 'schedule', company: 'somosemp', code: 850, time_zone: 'America/Sao_Paulo', title: 'OS 850', location: 'Rua A',
                                   start: '2026-11-26T09:00', end: '2026-11-26T11:00', calendars: %w[google],
                                   attendees: %w[marcos@rota.com.br teo@gmail.com],
                                   whatsapp: { contact_ids: [marcos.id, julia.id], inbox_id: inbox.id, message: 'Olá, {contato}! Agendado.' })
    expect(response).to have_http_status(:created)
    expect(created).to have_been_requested
    expect(body['whatsapp']).to eq(2)
    expect(body['substatus']).to eq('ok' => false, 'reason' => 'write_disabled')
    expect(body['schedule']).to include('start' => '2026-11-26T09:00:00', 'mine' => true, 'whatsapp_count' => 2,
                                        'calendars' => [{ 'provider' => 'google', 'web_link' => 'https://calendar.google.com/ev1' }])
    expect(Message.where(account_id: account.id).order(:id).pluck(:content)).to eq(['Olá, Marcos! Agendado.', 'Olá, Júlia! Agendado.'])

    list = call(:get, 'schedule', company: 'somosemp', code: 850)['schedules']
    expect(list.pluck('title')).to eq(['OS 850'])

    removed = stub_request(:delete, 'https://www.googleapis.com/calendar/v3/calendars/primary/events/ev1?sendUpdates=all').to_return(status: 204)
    send(:delete, "#{base}/schedule/#{list.first['id']}", headers: agent.create_new_auth_token, as: :json)
    expect(response).to have_http_status(:no_content)
    expect(removed).to have_been_requested
    expect(Outsider::Erp::OrderSchedule.count).to eq(0)
  end

  it 'writes the Observações of the OS in the description (Defeitos only when there are none, never a lone dot)' do
    detail['header'].merge!('observacoes' => 'Levar mangueira', 'defeitos' => '.')
    body = call(:get, 'schedule', company: 'somosemp', code: 850)['event']['body']
    expect(body).to include('Observações: Levar mangueira')
    expect(body).not_to include('Defeitos')
    detail['header']['observacoes'] = ' . '
    expect(call(:get, 'schedule', company: 'somosemp', code: 850)['event']['body']).not_to include('Defeitos', 'Observações')
  end

  it 'books in the calendar the person picked (a shared one) and cancels it there' do
    created = stub_request(:post, %r{googleapis.com/calendar/v3/calendars/tec@group.calendar.google.com/events})
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                         body: { id: 'ev3', status: 'confirmed', start: { dateTime: '2026-11-26T09:00:00-03:00' } }.to_json)
    call(:post, 'schedule', company: 'somosemp', code: 850, title: 'OS 850', start: '2026-11-26T09:00', end: '2026-11-26T10:00',
                            calendars: %w[google], calendar_ids: { google: 'tec@group.calendar.google.com' })
    expect(created).to have_been_requested
    schedule = Outsider::Erp::OrderSchedule.sole
    removed = stub_request(:delete, %r{calendars/tec@group.calendar.google.com/events/ev3}).to_return(status: 204)
    send(:delete, "#{base}/schedule/#{schedule.id}", headers: agent.create_new_auth_token, as: :json)
    expect(removed).to have_been_requested
  end

  it 'moves the OS to the AGENDADO substatus of its unit after booking' do
    allow_any_instance_of(Outsider::Erp::Settings).to receive(:write_enabled?).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Erp::Writer).to receive(:substatus_choices).and_return(['1-AGENDAR (DF)', '2-AGENDADO (DF)']) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Erp::Writer).to receive(:substatus) # rubocop:disable RSpec/AnyInstance
      .with(company: 'somosemp', code: 850, value: '2-AGENDADO (DF)').and_return('SubStatus' => '2-AGENDADO (DF)')
    stub_request(:post, %r{googleapis.com/calendar/v3/calendars/primary/events})
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { id: 'ev2', status: 'confirmed', start: { dateTime: '2026-11-26T09:00:00-03:00' } }.to_json)
    body = call(:post, 'schedule', company: 'somosemp', code: 850, title: 'OS 850', start: '2026-11-26T09:00', end: '2026-11-26T10:00',
                                   calendars: %w[google])
    expect(body['substatus']).to eq('ok' => true, 'value' => '2-AGENDADO (DF)')
  end

  it 'tells whether the checklist of the OS already came back answered' do
    Rails.cache.clear
    allow_any_instance_of(Outsider::Erp::Client).to receive(:service_order_report) # rubocop:disable RSpec/AnyInstance
      .with('DadosCheckList_PDF', 'somosemp', 850).and_return([{ 'VALOR_INI' => '', 'CaminhoIMG' => '' }])
    expect(call(:get, 'checklist', company: 'somosemp', code: 850)['answered']).to be(false)
    allow_any_instance_of(Outsider::Erp::Client).to receive(:service_order_report) # rubocop:disable RSpec/AnyInstance
      .with('DadosCheckList_PDF', 'somosemp', 851).and_return([{ 'VALOR_INI' => '', 'CaminhoIMG' => '851_1' }])
    expect(call(:get, 'checklist', company: 'somosemp', code: 851)['answered']).to be(true)
  end

  it 'refuses a calendar that is not connected and a WhatsApp list over the limit, before booking anything' do
    body = call(:post, 'schedule', company: 'somosemp', code: 850, title: 'OS 850', start: '2026-11-26T09:00', end: '2026-11-26T10:00',
                                   calendars: %w[microsoft])
    expect(body['reason']).to eq('calendar_not_ready')

    many = create_list(:contact, 6, account: account).each_with_index { |contact, i| contact.update!(phone_number: "+55629999900#{10 + i}") }
    body = call(:post, 'schedule', company: 'somosemp', code: 850, title: 'OS 850', start: '2026-11-26T09:00', end: '2026-11-26T10:00',
                                   calendars: %w[google], whatsapp: { contact_ids: many.map(&:id), inbox_id: inbox.id, message: 'Oi' })
    expect(body['reason']).to eq('too_many_whatsapp')
    expect(Outsider::Erp::OrderSchedule.count).to eq(0)
  end

  it 'sends a plain WhatsApp text and stops at the hourly limit' do
    body = call(:post, 'message', company: 'somosemp', code: 850, contact_ids: [marcos.id], inbox_id: inbox.id, message: 'Olá, {contato}!')
    expect(body['sent']).to eq(1)
    Redis::Alfred.set("outsider:erp:whatsapp:#{account.id}:#{agent.id}:#{Time.current.strftime('%Y%m%d%H')}", 30)
    body = call(:post, 'message', company: 'somosemp', code: 850, contact_ids: [marcos.id], inbox_id: inbox.id, message: 'De novo')
    expect(body['reason']).to eq('whatsapp_limit')
  end

  it 'finds contacts and colleagues to invite' do
    marcos
    body = call(:get, 'people', q: 'marc')
    expect(body['contacts'].pluck('email')).to eq(['marcos@rota.com.br'])
    expect(call(:get, 'people', q: 'téo')['users'].pluck('email')).to eq(['teo@empresa.com'])
  end

  it 'sends the OS report to several WhatsApp contacts at once, each greeted by name' do
    document = instance_double(Outsider::Erp::Prints::Document, render: '%PDF-1.4', filename: 'OS-850.pdf')
    allow(Outsider::Erp::Prints::Document).to receive(:service_order).and_return(document)
    call(:post, 'deliver', company: 'somosemp', code: 850, channel: 'whatsapp', contact_ids: [marcos.id, julia.id], inbox_id: inbox.id,
                           message: 'Olá, {contato}! Segue o relatório.')
    expect(response).to have_http_status(:ok)
    messages = Message.where(account_id: account.id).order(:id)
    expect(messages.pluck(:content)).to eq(['Olá, Marcos! Segue o relatório.', 'Olá, Júlia! Segue o relatório.'])
    expect(messages.map { |message| message.attachments.size }).to eq([1, 1])
  end
end
