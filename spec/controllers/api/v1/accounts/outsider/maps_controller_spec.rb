require 'rails_helper'

# OUTSIDER: Google Maps na agenda: chave do Maps (navegador), locais do cliente e o local exato no agendamento da OS.
RSpec.describe 'Outsider maps and client places', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Transportes Rota', phone_number: '+5562999990001') }
  let(:places_url) { "/api/v1/accounts/#{account.id}/outsider/contacts/#{contact.id}/places" }
  let(:maps_url) { "/api/v1/accounts/#{account.id}/outsider/maps" }

  def json(verb, url, user, params = {})
    send(verb, url, params: params, headers: user.create_new_auth_token, as: :json)
    response.parsed_body
  end

  describe 'Google Maps key' do
    it 'is read by everyone and changed only by an administrator' do # rubocop:disable RSpec/MultipleExpectations
      expect(json(:get, maps_url, agent)).to eq('key' => nil, 'map_id' => nil, 'can_manage' => false)
      json(:put, maps_url, agent, key: 'AIzaSyAbcdefghijklmnopqrstuvwxyz012345')
      expect(response).to have_http_status(:forbidden)

      expect(json(:put, maps_url, admin, key: ' AIzaSyAbcdefghijklmnopqrstuvwxyz012345 ')['key']).to eq('AIzaSyAbcdefghijklmnopqrstuvwxyz012345')
      expect(json(:get, maps_url, agent)['key']).to eq('AIzaSyAbcdefghijklmnopqrstuvwxyz012345')

      expect(json(:put, maps_url, admin, key: 'not a key!')).to eq('error' => 'invalid_key')
      expect(json(:put, maps_url, admin, key: 'AIzaSyAbcdefghijklmnopqrstuvwxyz012345', map_id: '8f2b1a0c9d3e')['map_id']).to eq('8f2b1a0c9d3e')
      expect(json(:put, maps_url, admin, key: 'AIzaSyAbcdefghijklmnopqrstuvwxyz012345', map_id: 'bad id!')).to eq('error' => 'invalid_map_id')
      expect(json(:put, maps_url, admin, key: '')['key']).to be_nil
      expect(json(:get, maps_url, agent)['map_id']).to eq('8f2b1a0c9d3e')
    end
  end

  describe 'client places' do
    it 'keeps one main place, moves the mark and passes it on when the main one is deleted' do
      first = json(:post, places_url, agent, place: { name: 'Galpão', address: 'Rua 10, 250', latitude: '-16,680001', longitude: -49.25 })
      expect(response).to have_http_status(:created)
      expect(first).to include('name' => 'Galpão', 'latitude' => -16.680001, 'main' => true)

      second = json(:post, places_url, agent, place: { address: 'Av. Brasil, 1200, Anápolis', latitude: -16.33, longitude: -48.95 })
      expect(second).to include('name' => 'Av. Brasil', 'main' => false)
      expect(json(:post, places_url, agent, place: { name: 'De novo', latitude: -16.33, longitude: -48.95 })['id']).to eq(second['id'])

      json(:patch, "#{places_url}/#{second['id']}", agent, place: { main: true })
      expect(json(:get, places_url, agent)['payload'].map { |row| row.values_at('id', 'main') }).to eq([[second['id'], true], [first['id'], false]])

      json(:delete, "#{places_url}/#{second['id']}", agent)
      expect(json(:get, places_url, agent)['payload'].map { |row| row.values_at('id', 'main') }).to eq([[first['id'], true]])
    end

    it 'refuses invalid coordinates and other accounts contacts' do
      expect(json(:post, places_url, agent, place: { name: 'X', latitude: 120, longitude: 10 })).to eq('error' => 'invalid_coordinates')
      other = create(:contact)
      json(:get, "/api/v1/accounts/#{account.id}/outsider/contacts/#{other.id}/places", agent)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'exact place on the OS schedule' do
    let(:inbox) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/somos').inbox }
    let(:scopes) { (%w[openid email profile] + Outsider::GoogleLink::FEATURES.values).join(' ') }
    let(:base) { "/api/v1/accounts/#{account.id}/outsider/erp/service_orders" }
    let(:detail) do
      { 'kind' => 'orders', 'company' => 'somosemp', 'numero' => 850, 'contact_id' => contact.id,
        'header' => { 'atendimento' => 'PREVENTIVA', 'previsao' => '2026-11-26 00:00:00' }, 'cliente' => { 'nome' => 'Transportes Rota' } }
    end
    let(:place) { { name: 'Galpão', address: 'Rua 10, 250', latitude: -16.680001, longitude: -49.25 } }

    before do
      create(:inbox_member, user: agent, inbox: inbox)
      Outsider::Erp::Settings.new(account).update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc123')
      allow_any_instance_of(Outsider::Erp::Records::Detail).to receive(:build).and_return(detail) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Outsider::Erp::Lists).to receive(:technicians).and_return([]) # rubocop:disable RSpec/AnyInstance
      Outsider::GoogleLink.create!(account: account, user: agent, google_user_id: 'g-1', email: 'ana@gmail.com', display_name: 'Ana',
                                   access_token: 'token-g', refresh_token: 'refresh-g', token_expires_at: 1.hour.from_now, scopes: scopes)
      Redis::Alfred.delete("outsider:erp:whatsapp:#{account.id}:#{agent.id}:#{Time.current.strftime('%Y%m%d%H')}")
    end

    it 'suggests the client places, books the event with the point and the Maps link, keeps the place and sends the pin' do # rubocop:disable RSpec/MultipleExpectations
      Outsider::ContactPlaces.new(contact).create(name: 'Filial', latitude: -16.33, longitude: -48.95)
      expect(json(:get, "#{base}/schedule", agent, company: 'somosemp', code: 850)['places'].pluck('name')).to eq(['Filial'])

      sent = nil
      created = stub_request(:post, %r{calendars/primary/events}).with { |request| sent = JSON.parse(request.body) }
                                                                 .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                                                            body: { id: 'ev1', htmlLink: 'https://calendar.google.com/ev1',
                                                                                    start: { dateTime: '2026-11-26T09:00:00-03:00' },
                                                                                    end: { dateTime: '2026-11-26T11:00:00-03:00' } }.to_json)
      body = nil
      expect do
        body = json(:post, "#{base}/schedule", agent, company: 'somosemp', code: 850, time_zone: 'America/Sao_Paulo', title: 'OS 850',
                                                      start: '2026-11-26T09:00', end: '2026-11-26T11:00', calendars: %w[google], body: 'Visita',
                                                      place: place, save_place: true,
                                                      whatsapp: { contact_ids: [contact.id], inbox_id: inbox.id, message: 'Agendado.',
                                                                  send_location: true })
      end.to have_enqueued_job(Outsider::Erp::ScheduleLocationJob)
      expect(created).to have_been_requested
      expect(sent['location']).to eq('Galpão - Rua 10, 250')
      expect(sent['description']).to eq("Visita\n\nLocal no Google Maps: https://www.google.com/maps/search/?api=1&query=-16.680001,-49.25")
      expect(sent.dig('extendedProperties', 'private')).to eq('outsider_latitude' => '-16.680001', 'outsider_longitude' => '-49.25')
      expect(body['schedule']['place']).to eq('name' => 'Galpão', 'latitude' => -16.680001, 'longitude' => -49.25)
      expect(Outsider::ContactPlaces.new(contact).all.map(&:name)).to eq(%w[Filial Galpão])
    end
  end
end
