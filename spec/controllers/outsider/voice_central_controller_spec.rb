require 'rails_helper'

RSpec.describe 'Outsider voice central', type: :request do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:token) { 'a' * 40 }
  let(:headers) { { 'X-Voice-Token' => token } }
  let(:base) { "/outsider/voice/central/#{account.id}" }

  around { |example| with_modified_env(OUTSIDER_VOICE_TOKEN: token) { example.run } }

  before do
    Outsider::Voice::Settings.new(account).update(
      'enabled' => true, 'ws_url' => 'wss://voip.exemplo.com.br/ws', 'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }],
      'trunk' => { 'host' => 'sip.operadora.com.br', 'username' => 'somos', 'password' => 'segredo' },
      'agents' => { seller.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true } }
    )
  end

  it 'answers 404 without the token or with a short one' do
    get "#{base}/pjsip"
    expect(response).to have_http_status(:not_found)

    with_modified_env(OUTSIDER_VOICE_TOKEN: 'curto') do
      get "#{base}/pjsip", headers: { 'X-Voice-Token' => 'curto' }
    end
    expect(response).to have_http_status(:not_found)
  end

  it 'gives the central the extensions and the operator account' do
    get "#{base}/pjsip", headers: headers

    expect(response.body).to include('[201]', 'type=endpoint', 'webrtc=yes', 'from_domain=voip.exemplo.com.br',
                                     'server_uri=sip:sip.operadora.com.br:5060',
                                     'password=segredo')
    get "#{base}/extensions", headers: headers
    expect(response.body).to include('ALL_AGENTS=PJSIP/201')
  end

  it 'routes a call and records it until the end' do
    post "#{base}/inbound", params: { linkedid: 'L1', did: '6232345678', from: '62999998888' }, headers: headers
    expect(response.body).to eq('20|PJSIP/201')

    post "#{base}/answered", params: { linkedid: 'L1', endpoint: '201' }, headers: headers
    post "#{base}/hangup", params: { linkedid: 'L1', dialstatus: 'ANSWER', cause: '16' }, headers: headers

    expect(Outsider::Voice::Call.find_by!(linkedid: 'L1')).to have_attributes(status: 'answered', user_id: seller.id)
  end

  it 'keeps the state the central reports' do
    post "#{base}/status", params: { registration: 'Registered', extensions: '201' }, headers: headers

    expect(Outsider::Voice::CentralStatus.new(account).to_h).to include(online: true, registration: 'Registered', extensions: ['201'])
  end
end
