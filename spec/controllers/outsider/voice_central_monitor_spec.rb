require 'rails_helper'

RSpec.describe 'Outsider voice central: monitoring and IVR', type: :request do
  let(:account) { create(:account) }
  let(:unit) { crm_unit(account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:token) { 'a' * 40 }
  let(:headers) { { 'X-Voice-Token' => token } }
  let(:base) { "/outsider/voice/central/#{account.id}" }

  around { |example| with_modified_env(OUTSIDER_VOICE_TOKEN: token) { example.run } }

  before do
    Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: agent, role: :seller)
    Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: manager, role: :manager)
    Outsider::Voice::Settings.new(account).update(
      'enabled' => true, 'ws_url' => 'wss://voip.exemplo.com.br/ws', 'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }],
      'agents' => { agent.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true },
                    manager.id.to_s => { 'extension' => '202', 'state' => 'GO', 'enabled' => true },
                    colleague.id.to_s => { 'extension' => '203', 'state' => 'GO', 'enabled' => true } }
    )
  end

  def monitor(extension, target, mode, linkedid: "M-#{extension}-#{mode}")
    post "#{base}/monitor", params: { linkedid: linkedid, extension: extension, target: target, mode: mode }, headers: headers
    response.body
  end

  it 'lets the unit manager listen and whisper, and records every monitoring until it ends' do
    expect(monitor('202', '201', 'listen')).to eq('ok')
    expect(monitor('202', '201', 'whisper')).to eq("supervisor:#{manager.id}")

    records = Outsider::Voice::Monitor.where(account_id: account.id)
    expect(records.pluck(:user_id, :target_user_id, :mode, :kind)).to contain_exactly(
      [manager.id, agent.id, 'listen', 'supervisor'], [manager.id, agent.id, 'whisper', 'supervisor']
    )

    post "#{base}/hangup", params: { linkedid: 'M-202-listen', dialstatus: 'ANSWER' }, headers: headers
    expect(records.find_by(linkedid: 'M-202-listen').ended_at).to be_present
  end

  it 'refuses an agent spying on a colleague or on the manager, and accepts a colleague only with an invite, once' do
    expect(monitor('201', '202', 'listen')).to eq('')
    expect(monitor('203', '201', 'whisper')).to eq('')

    Outsider::Voice::Signals.new(Outsider::Voice::Settings.new(account), agent).deliver(type: 'invite', to_user_id: colleague.id,
                                                                                        data: { customer: 'Cliente' })
    expect(monitor('203', '201', 'listen')).to eq('')
    expect(monitor('203', '201', 'whisper', linkedid: 'G1')).to eq("guest:#{colleague.id}")
    expect(monitor('203', '201', 'whisper', linkedid: 'G2')).to eq('')
  end

  it 'answers the IVR steps, the audio list and keeps the voicemail on the call' do
    Outsider::Voice::IvrFlow.create!(
      account: account, name: 'URA', active: true,
      graph: { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'data' => {} },
                           { 'id' => 'vm', 'type' => 'voicemail', 'data' => { 'prompt' => { 'text' => 'Deixe o recado' } } }],
               'edges' => [{ 'from' => 'start', 'port' => 'next', 'to' => 'vm' }] }
    )
    post "#{base}/inbound", params: { linkedid: 'IN1', did: '6232345678', from: '62999998888' }, headers: headers
    expect(response.body).to eq('ivr')

    post "#{base}/ivr", params: { linkedid: 'IN1' }, headers: headers
    name = response.body[%r{outsider/(\h{20})}, 1]
    expect(response.body).to eq("record|outsider/#{name}|120|vm")

    get "#{base}/prompts", headers: headers
    expect(response.body).to eq("#{name}|tts|#{Base64.strict_encode64('Deixe o recado')}")

    file = Rack::Test::UploadedFile.new(StringIO.new('RIFF....WAVE'), 'audio/wav', original_filename: 'IN1.wav')
    post "#{base}/voicemail", params: { linkedid: 'IN1', file: file }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Outsider::Voice::Call.find_by!(linkedid: 'IN1').voicemail).to be_attached
  end
end
