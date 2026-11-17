require 'rails_helper'

# OUTSIDER: foto do perfil das pessoas do Teams (Outsider::Teams::Graph::Photo / Outsider::TeamsPhotosController)
RSpec.describe Outsider::Teams::Graph::Photo, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ms_id) { '11111111-2222-3333-4444-555555555555' }
  let(:link) do
    Outsider::TeamsLink.create!(account: account, user: user, ms_user_id: '99999999-2222-3333-4444-555555555555', status: 'active',
                                access_token: 'tok', refresh_token: 'ref', token_expires_at: 1.hour.from_now)
  end
  let(:base) { "https://graph.microsoft.com/v1.0/users/#{ms_id}" }

  before { Redis::Alfred.delete("outsider_teams_photo:#{account.id}:#{ms_id}") }

  it 'gives a signed address, serves the photo and keeps it in Redis' do
    photo = stub_request(:get, "#{base}/photos/96x96/$value").to_return(status: 200, body: 'JPEGDATA', headers: { 'Content-Type' => 'image/jpeg' })
    url = described_class.url(link, ms_id)
    expect(url).to start_with('/outsider/teams/photo?t=')
    expect(described_class.url(link, 'not-an-id')).to be_nil

    2.times do
      get url
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('JPEGDATA')
      expect(response.media_type).to eq('image/jpeg')
    end
    expect(photo).to have_been_requested.once
  end

  it 'falls back to the default photo and answers 404 when there is none' do
    stub_request(:get, "#{base}/photos/96x96/$value").to_return(status: 404, body: '{}')
    fallback = stub_request(:get, "#{base}/photo/$value").to_return(status: 404, body: '{}')
    get described_class.url(link, ms_id)
    expect(response).to have_http_status(:not_found)
    get described_class.url(link, ms_id)
    expect(fallback).to have_been_requested.once
    get '/outsider/teams/photo?t=forjado'
    expect(response).to have_http_status(:not_found)
  end

  it 'adds the photo to messages and people' do
    thread = link.threads.create!(kind: 'chat', chat_id: '19:x', chat_type: 'oneOnOne', title: 'Ana',
                                  members: [{ 'id' => ms_id, 'name' => 'Ana' }, { 'id' => link.ms_user_id, 'name' => 'Eu' }])
    message = thread.messages.create!(sender_name: 'Ana', sender_ms_id: ms_id, content: 'oi', sent_at: Time.current, graph_id: 'g1',
                                      status: 'sent')
    json = Outsider::Teams::Graph::Json
    expect(json.message(message)[:sender_photo]).to start_with('/outsider/teams/photo?t=')
    expect(json.thread(thread)[:peer_photo]).to start_with('/outsider/teams/photo?t=')
    expect(described_class.read(json.thread(thread)[:peer_photo].split('t=').last)).to include('l' => link.id, 'u' => ms_id)
  end
end
