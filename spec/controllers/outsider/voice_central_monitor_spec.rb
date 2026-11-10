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
    expect(monitor('202', '201', 'whisper')).to eq("supervisor:#{manager.id}:whisper")

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

    signals = Outsider::Voice::Signals.new(Outsider::Voice::Settings.new(account), agent)
    signals.deliver(type: 'invite', to_user_id: colleague.id, data: { customer: 'Cliente' })
    expect(monitor('203', '201', 'listen')).to eq('')
    expect(monitor('203', '201', 'whisper', linkedid: 'G1')).to eq("guest:#{colleague.id}:open")
    expect(Outsider::Voice::Monitor.find_by!(linkedid: 'G1').opened_at).to be_present
    expect(monitor('203', '201', 'whisper', linkedid: 'G2')).to eq('')
  end

  it 'lets the invited colleague join only talking to the agent when invited to whisper' do
    Outsider::Voice::Signals.new(Outsider::Voice::Settings.new(account), agent)
                            .deliver(type: 'invite', to_user_id: colleague.id, data: { customer: 'Cliente', mode: 'whisper' })

    expect(monitor('203', '201', 'whisper', linkedid: 'G3')).to eq("guest:#{colleague.id}:whisper")
    expect(Outsider::Voice::Monitor.find_by!(linkedid: 'G3').opened_at).to be_nil
  end

  it 'gives the central the whole dialplan, so a new one needs no container rebuild' do
    get "#{base}/extensions", headers: headers
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(Outsider::Voice::CentralStatus.new(account).to_h).to include(dialplan: 'ok', telephony_version: '26f')
    expect(response.body).to include('telefonia 26f', 'ALL_AGENTS=PJSIP/201&PJSIP/202&PJSIP/203', '[from-agents]',
                                     'exten => _*80[1-5]XX', 'exten => _*81[1-5]XX', '[outsider-ivr]', '(whisper|open)',
                                     '/ivr_missing', 'STAT(e,/usr/share/asterisk/sounds/outsider/${AUDIO}.wav)')
  end

  it 'tells when the central talks to another Chatwoot or does not fetch the dialplan here' do
    stub_const('Outsider::Voice::CentralStatus::LOADED_AT', 10.minutes.ago)
    status = Outsider::Voice::CentralStatus.new(account)
    # o Chatwoot antigo, no mesmo Redis, grava o aviso da central sem a versão dele
    Redis::Alfred.setex("outsider_voice_status:#{account.id}", { at: Time.current.to_i, registration: 'Registered' }.to_json, 60)
    expect(status.to_h).to include(online: true, dialplan: 'other', chatwoot: nil)

    post "#{base}/status", params: { registration: 'Registered', extensions: '201' }, headers: headers
    expect(status.to_h).to include(dialplan: 'missing', chatwoot: '26f')

    stub_const('Outsider::Voice::CentralStatus::LOADED_AT', 1.minute.ago)
    expect(status.to_h[:dialplan]).to eq('waiting')
  end

  it 'rings the sales team instead of the IVR while the central has no audio programs' do
    Outsider::Voice::IvrFlow.create!(account: account, name: 'URA', active: true, graph: {})
    post "#{base}/status", params: { registration: 'Registered', extensions: '201' }, headers: headers
    post "#{base}/inbound", params: { linkedid: 'OLD1', did: '6232345678', from: '62999998888' }, headers: headers
    expect(response.body).to start_with('20|')

    post "#{base}/status", params: { registration: 'Registered', extensions: '201', version: '26', audio: 'yes' }, headers: headers
    post "#{base}/inbound", params: { linkedid: 'NEW1', did: '6232345678', from: '62999998888' }, headers: headers
    expect(response.body).to eq('ivr||20|PJSIP/201&PJSIP/202&PJSIP/203')
  end

  it 'trusts the first Entrega 26 central, which syncs the IVR audios without telling its version' do
    Outsider::Voice::IvrFlow.create!(account: account, name: 'URA', active: true, graph: {})
    post "#{base}/status", params: { registration: 'Registered', extensions: '201' }, headers: headers
    get "#{base}/prompts", headers: headers

    post "#{base}/inbound", params: { linkedid: 'IVR26', did: '6232345678', from: '62999998888' }, headers: headers
    expect(response.body).to start_with('ivr||20|')
  end

  it 'takes the call out of the IVR and warns when the central has not got one of its audios' do
    flow = Outsider::Voice::IvrFlow.create!(
      account: account, name: 'URA', active: true,
      graph: { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'data' => {} },
                           { 'id' => 'hello', 'type' => 'say', 'data' => { 'prompt' => { 'text' => 'Olá' } } }],
               'edges' => [{ 'from' => 'start', 'port' => 'next', 'to' => 'hello' }] }
    )
    status = Outsider::Voice::CentralStatus.new(account)
    status.report(registration: 'Registered', extensions: [], version: 26, audio: true)
    post "#{base}/inbound", params: { linkedid: 'MUDA1', did: '6232345678', from: '62999998888' }, headers: headers
    expect(Outsider::Voice::Call.find_by!(linkedid: 'MUDA1').ivr_flow).to eq(flow)

    post "#{base}/ivr_missing", params: { linkedid: 'MUDA1', audio: 'a' * 20 }, headers: headers
    expect(Outsider::Voice::Call.find_by!(linkedid: 'MUDA1')).to have_attributes(ivr_flow: nil, ivr_data: {})
    expect(status.to_h[:ivr_audio_missing]).to include(flow: 'URA', at: be_within(5.seconds).of(Time.current))

    # a ligação seguinte entra na URA: a central já tem os áudios
    post "#{base}/inbound", params: { linkedid: 'FALA1', did: '6232345678', from: '62999998888' }, headers: headers
    post "#{base}/ivr", params: { linkedid: 'FALA1' }, headers: headers
    expect(status.to_h[:ivr_audio_missing]).to be_nil
  end

  it 'answers the IVR steps, the audio list and keeps the voicemail on the call' do
    Outsider::Voice::IvrFlow.create!(
      account: account, name: 'URA', active: true,
      graph: { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'data' => {} },
                           { 'id' => 'vm', 'type' => 'voicemail', 'data' => { 'prompt' => { 'text' => 'Deixe o recado' } } }],
               'edges' => [{ 'from' => 'start', 'port' => 'next', 'to' => 'vm' }] }
    )
    Outsider::Voice::CentralStatus.new(account).report(registration: 'Registered', extensions: [], version: 26, audio: true)
    post "#{base}/inbound", params: { linkedid: 'IN1', did: '6232345678', from: '62999998888' }, headers: headers
    name = response.body[/\Aivr\|(\h{20})\|20\|PJSIP/, 1]
    expect(name).to be_present

    post "#{base}/ivr", params: { linkedid: 'IN1' }, headers: headers
    expect(response.body).to eq("record|outsider/#{name}|120|vm")

    get "#{base}/prompts", headers: headers
    expect(response.body).to eq("#{name}|tts|#{Base64.strict_encode64('Deixe o recado')}")

    file = Rack::Test::UploadedFile.new(StringIO.new('RIFF....WAVE'), 'audio/wav', original_filename: 'IN1.wav')
    post "#{base}/voicemail", params: { linkedid: 'IN1', file: file }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Outsider::Voice::Call.find_by!(linkedid: 'IN1').voicemail).to be_attached
  end
end
