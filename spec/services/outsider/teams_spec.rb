require 'rails_helper'

RSpec.describe 'Outsider Microsoft Teams bridge', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: Channel::Api.create!(account: account)) }
  let(:app_id) { '11111111-2222-3333-4444-555555555555' }
  let(:connection) do
    Outsider::TeamsConnection.create!(account: account, inbox: inbox, app_id: app_id, tenant_id: '99999999-8888-7777-6666-555555555555',
                                      app_password: 'segredo')
  end
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(rsa, kid: 'chave-1') }
  let(:service_url) { 'https://smba.trafficmanager.net/br/' }
  let(:activity) do
    { 'type' => 'message', 'id' => 'act-1', 'channelId' => 'msteams', 'serviceUrl' => service_url, 'text' => 'Olá, preciso de ajuda',
      'from' => { 'id' => '29:abc', 'name' => 'Maria Souza', 'aadObjectId' => 'aad-1' }, 'recipient' => { 'id' => '28:bot' },
      'conversation' => { 'id' => 'a:conversa-1', 'conversationType' => 'personal', 'tenantId' => 'tenant' } }
  end

  def bearer(claims = {})
    payload = { iss: 'https://api.botframework.com', aud: app_id, exp: 10.minutes.from_now.to_i, nbf: 1.minute.ago.to_i,
                serviceurl: service_url }.merge(claims)
    "Bearer #{JWT.encode(payload, rsa, 'RS256', kid: 'chave-1')}"
  end

  before do
    jwks = 'https://login.botframework.com/v1/.well-known/keys'
    stub_request(:get, Outsider::Teams::Auth::OPENID).to_return(body: { jwks_uri: jwks }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, jwks).to_return(body: { keys: [jwk.export.merge(endorsements: ['msteams'])] }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  it 'accepts only messages signed by the Bot Framework for this bot' do
    auth = Outsider::Teams::Auth.new(connection)
    expect(auth.verify!(bearer, activity)).to include('aud' => app_id)

    expect { auth.verify!(bearer(aud: 'outro-robo'), activity) }.to raise_error(Outsider::Teams::Auth::Invalid)
    expect { auth.verify!(bearer(serviceurl: 'https://evil.example.com/'), activity) }.to raise_error(Outsider::Teams::Auth::Invalid)
    expect { auth.verify!(bearer, activity.merge('channelId' => 'slack')) }.to raise_error(Outsider::Teams::Auth::Invalid)
    other_key = OpenSSL::PKey::RSA.generate(2048)
    forged = "Bearer #{JWT.encode({ iss: 'https://api.botframework.com', aud: app_id, exp: 1.hour.from_now.to_i }, other_key, 'RS256',
                                  kid: 'chave-1')}"
    expect { auth.verify!(forged, activity) }.to raise_error(Outsider::Teams::Auth::Invalid)
  end

  it 'turns a Teams message into a conversation once, and replies through the Bot Connector' do
    message = Outsider::Teams::Inbound.new(connection, activity).perform
    expect(message.content).to eq('Olá, preciso de ajuda')
    expect(message.sender.name).to eq('Maria Souza')
    expect(message.conversation.additional_attributes['teams']).to include('conversation_id' => 'a:conversa-1', 'service_url' => service_url)
    expect(Outsider::Teams::Inbound.new(connection, activity).perform).to be_nil
    expect(inbox.messages.count).to eq(1)

    stub_request(:post, %r{login.microsoftonline.com/.+/oauth2/v2.0/token}).to_return(
      status: 200, body: { access_token: 'token-robo' }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    sent = stub_request(:post, "#{service_url}v3/conversations/a%3Aconversa-1/activities")
           .with(headers: { 'Authorization' => 'Bearer token-robo' }, body: hash_including('type' => 'message', 'text' => 'Já vamos ajudar'))
           .to_return(status: 201, body: { id: 'resposta-1' }.to_json, headers: { 'Content-Type' => 'application/json' })
    reply = message.conversation.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Já vamos ajudar')
    Outsider::Teams::Outbound.new(connection, reply).perform

    expect(sent).to have_been_requested
    expect(reply.reload).to have_attributes(source_id: 'teams:resposta-1', status: 'sent')
  end

  it 'answers the webhook only with a valid signature and builds a valid app package' do
    post "/outsider/teams/#{connection.webhook_token}/messages", params: activity.to_json,
                                                                 headers: { 'Content-Type' => 'application/json', 'Authorization' => 'Bearer x' }
    expect(response).to have_http_status(:unauthorized)

    expect do
      post "/outsider/teams/#{connection.webhook_token}/messages", params: activity.to_json,
                                                                   headers: { 'Content-Type' => 'application/json', 'Authorization' => bearer }
    end.to have_enqueued_job(Outsider::Teams::ReceiveJob)
    expect(response).to have_http_status(:ok)

    post '/outsider/teams/nao-existe/messages', params: activity.to_json, headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:not_found)

    zip = Outsider::Teams::AppPackage.new(connection, site: 'https://chat.exemplo.com.br').to_zip
    expect(zip.byteslice(0, 4)).to eq("PK\x03\x04".b)
    manifest_start = zip.index('{')
    manifest = JSON.parse(zip.byteslice(manifest_start, zip.index("\n}", manifest_start) + 2 - manifest_start))
    expect(manifest).to include('id' => app_id, 'bots' => [include('botId' => app_id)], 'validDomains' => ['chat.exemplo.com.br'])
  end
end
