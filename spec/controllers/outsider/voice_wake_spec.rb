require 'rails_helper'

# OUTSIDER (técnicos): a ligação que acorda o celular (Outsider::Voice::Wake) e o perfil Técnico na API
RSpec.describe 'Outsider voice central: wake the technician phone', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:technician) { create(:user, account: account, role: :agent) }
  let(:token) { 'a' * 40 }
  let(:headers) { { 'X-Voice-Token' => token } }
  let(:base) { "/outsider/voice/central/#{account.id}" }
  let(:technician_profile) { Outsider::Access::Defaults.new(account).ensure!.find_by(kind: 'technician') }

  around { |example| with_modified_env(OUTSIDER_VOICE_TOKEN: token) { example.run } }

  before do
    Outsider::Voice::Settings.new(account).update(
      'enabled' => true, 'ws_url' => 'wss://voip.exemplo.com.br/ws',
      'agents' => { agent.id.to_s => { 'extension' => '201', 'enabled' => true },
                    technician.id.to_s => { 'extension' => '230', 'enabled' => true, 'inbound' => false } }
    )
    Outsider::AccessMember.create!(account: account, user: technician, profile: technician_profile)
  end

  def wake(linkedid = 'L1')
    post "#{base}/wake", params: { linkedid: linkedid, extension: '201', target: '230' }, headers: headers
    response.body
  end

  def wake_status(linkedid = 'L1')
    post "#{base}/wake_status", params: { linkedid: linkedid, target: '230' }, headers: headers
    response.body
  end

  def wake_jobs
    enqueued_jobs.select { |job| job['job_class'] == 'Outsider::Voice::WakeJob' }.map { |job| job['arguments'].last }
  end

  it 'does not hold the call when the technician has no phone notice turned on' do
    expect(wake).to eq('0')
    expect(wake_jobs).to be_empty
  end

  context 'with the notice turned on in the phone' do
    before { create(:notification_subscription, :browser_push, user: technician) }

    it 'rings the phone, waits longer after Atender and stops the notice when answered' do
      expect(wake).to eq(Outsider::Voice::Wake::WAIT.to_s)
      expect(wake_jobs).to eq(['ring'])
      expect(wake_status).to eq('wait')

      push_token = Outsider::Voice::Wake.token(account.id, 'L1', '230', technician.id)
      post '/outsider/push/call', params: { token: push_token, call_action: 'accept' }
      expect(response).to have_http_status(:no_content)
      expect(wake_status).to eq("accept|#{Outsider::Voice::Wake::ACCEPT_WAIT}")

      post "#{base}/hangup", params: { linkedid: 'L1', dialstatus: 'ANSWER' }, headers: headers
      expect(wake_jobs).to eq(%w[ring stop])
    end

    it 'gives busy to the caller on Recusar and sends a single notice' do
      wake
      push_token = Outsider::Voice::Wake.token(account.id, 'L1', '230', technician.id)
      post '/outsider/push/call', params: { token: push_token, call_action: 'decline' }
      expect(wake_status).to eq('decline')

      post "#{base}/hangup", params: { linkedid: 'L1', dialstatus: 'BUSY' }, headers: headers
      expect(wake_jobs).to eq(%w[ring declined])
    end

    it 'turns the notice into a missed call when nobody answers' do
      wake
      post "#{base}/hangup", params: { linkedid: 'L1', dialstatus: 'NOANSWER' }, headers: headers
      expect(wake_jobs).to eq(%w[ring missed])
    end

    it 'refuses a token from another call or a forged one' do
      wake
      other = Outsider::Voice::Wake.token(account.id, 'L2', '230', technician.id)
      post '/outsider/push/call', params: { token: other, call_action: 'accept' }
      expect(response).to have_http_status(:gone)
      post '/outsider/push/call', params: { token: 'forged', call_action: 'accept' }
      expect(response).to have_http_status(:unauthorized)
      expect(wake_status).to eq('wait')
    end

    it 'sends the ring notice like a WhatsApp call, with Atender and Recusar' do
      wake
      sent = []
      allow(Outsider::Push::Sender).to receive(:new).and_return(instance_double(Outsider::Push::Sender).tap do |sender|
        allow(sender).to receive(:deliver) { |payload, **| sent << payload }
      end)
      Outsider::Push::CallWake.new(account, 'L1', '230').deliver('ring')
      expect(sent.first).to include(call: 'wake', linkedid: 'L1', title: agent.name, answer_label: 'Atender', decline_label: 'Recusar')
      expect(sent.first[:url]).to end_with("/app/accounts/#{account.id}/meu-telefone")
      expect(Outsider::Voice::Wake.token_data(sent.first[:token])).to include('l' => 'L1', 'u' => technician.id)
    end
  end

  describe 'technician profile on the API' do
    it 'opens only the phone: conversations are refused and the CRM says why' do
      sign = ->(path) { get path, headers: technician.create_new_auth_token, as: :json }

      sign.call("/api/v1/accounts/#{account.id}/outsider/access")
      expect(response.parsed_body).to include('kind' => 'technician', 'home' => 'phone')

      sign.call("/api/v1/accounts/#{account.id}/conversations/meta")
      expect(response).to have_http_status(:forbidden)

      sign.call("/api/v1/accounts/#{account.id}/outsider/crm/access")
      expect(response.parsed_body).to include('enabled' => false, 'reason' => 'profile')
    end

    it 'keeps agents as they are' do
      get "/api/v1/accounts/#{account.id}/conversations/meta", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
