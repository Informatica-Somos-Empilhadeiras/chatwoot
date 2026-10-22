require 'rails_helper'

RSpec.describe 'Outsider locations', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/locations" }
  let(:place) { { name: 'Matriz', address: 'Goiânia', latitude: -16.68, longitude: -49.25 } }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'sends for whoever sees the conversation' do
    sender = instance_double(Outsider::LocationSender, perform: nil)
    allow(Outsider::LocationSender).to receive(:new).and_return(sender)

    post url, params: { conversation_id: conversation.display_id, location: place }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(Outsider::LocationSender).to have_received(:new)
      .with(conversation: conversation, user: agent, location: ActionController::Parameters.new(place).permit!)
  end

  it 'refuses an agent outside the inbox and answers errors with a code' do
    post url, params: { conversation_id: conversation.display_id, location: place }, headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    allow(Outsider::LocationSender).to receive(:new).and_raise(Outsider::EvolutionApi::Error, 'evolution_timeout')
    post url, params: { conversation_id: conversation.display_id, location: place }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('evolution_timeout')
  end

  it 'searches addresses and reports when the search service is down' do
    geocoder = instance_double(Outsider::Geocoder)
    allow(Outsider::Geocoder).to receive(:new).and_return(geocoder)
    allow(geocoder).to receive(:search).with('rua 1').and_return([place])

    get "#{url}/search", params: { q: 'rua 1' }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].first['name']).to eq('Matriz')

    allow(geocoder).to receive(:search).and_raise(Outsider::Geocoder::Error, 'timeout')
    get "#{url}/search", params: { q: 'rua 1' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to eq('geocoder_unavailable')
  end

  it 'lets only administrators save and delete places, and everyone use them' do
    post "#{url}/saved", params: { location: place }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{url}/saved", params: { location: place }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    id = response.parsed_body['id']

    get "#{url}/saved", headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('can_manage' => false)
    expect(response.parsed_body['payload'].pluck('name')).to eq(['Matriz'])

    delete "#{url}/saved/#{id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)

    delete "#{url}/saved/#{id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:no_content)
    expect(Outsider::SavedLocations.new(account.reload).all).to eq([])
  end
end
