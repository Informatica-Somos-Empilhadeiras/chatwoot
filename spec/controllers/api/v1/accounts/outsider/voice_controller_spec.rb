require 'rails_helper'

RSpec.describe 'Outsider voice API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider" }

  before do
    unit = crm_unit(account)
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
    settings.update(
      'enabled' => true, 'ws_url' => 'wss://voz.exemplo.com.br/ws', 'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }],
      'agents' => { seller.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true },
                    colleague.id.to_s => { 'extension' => '202', 'state' => 'SP', 'enabled' => true } }
    )
  end

  describe 'GET voice/me' do
    it 'gives the browser the extension and its password' do
      get "#{base}/voice/me", headers: seller.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('enabled' => true, 'extension' => '201', 'ws_url' => 'wss://voz.exemplo.com.br/ws',
                                              'password' => settings.sip_password(seller.id, '201'), 'echo_extension' => '600')
    end

    it 'has no phone for who has no extension' do
      get "#{base}/voice/me", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('enabled' => false)
    end
  end

  describe 'GET voice/team' do
    it 'lists the colleagues with an extension and who is connected' do
      Outsider::Voice::CentralStatus.new(account).report(registration: '', extensions: ['201'])

      get "#{base}/voice/team", headers: colleague.create_new_auth_token, as: :json

      expect(response.parsed_body.map { |row| row.slice('extension', 'online') })
        .to contain_exactly({ 'extension' => '201', 'online' => true }, { 'extension' => '202', 'online' => false })
    end
  end

  describe 'voice settings' do
    it 'is only for administrators and never returns the operator password' do
      get "#{base}/crm/voice_settings", headers: seller.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      patch "#{base}/crm/voice_settings", headers: admin.create_new_auth_token, as: :json,
                                          params: { settings: settings.as_json.merge('trunk' => { 'host' => 'sip.op.com.br', 'username' => 'u',
                                                                                                  'password' => 'segredo' }) }

      expect(response.parsed_body['settings']['trunk']).to include('host' => 'sip.op.com.br', 'password_set' => true)
      expect(response.body).not_to include('segredo')
      expect(Outsider::Voice::Settings.new(account.reload).trunk['password']).to eq('segredo')
    end

    it 'points out the wrong fields' do
      patch "#{base}/crm/voice_settings", headers: admin.create_new_auth_token, as: :json,
                                          params: { settings: settings.as_json.merge('ws_url' => 'http://x', 'numbers' => [{ 'number' => '190', 'state' => 'XX' }]) }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['fields']).to contain_exactly('ws_url', 'numbers.0.number', 'numbers.0.state')
    end
  end

  describe 'calls' do
    before do
      Outsider::Voice::Call.create!(account: account, linkedid: 'mine', direction: :outbound, status: :answered, user: seller,
                                    started_at: Time.current, talk_seconds: 120, to_number: '+5562999998888')
      Outsider::Voice::Call.create!(account: account, linkedid: 'theirs', direction: :outbound, status: :answered, user: colleague,
                                    started_at: Time.current, talk_seconds: 60, to_number: '+5511999998888')
      Outsider::Voice::Call.create!(account: account, linkedid: 'missed-go', direction: :inbound, status: :missed, state_code: 'GO',
                                    started_at: Time.current, from_number: '+5562988887777')
      Outsider::Crm::CallGoals.new(account).update(Outsider::Crm::MonthlyConfig.current_month,
                                                   users: { seller.id.to_s => { 'calls' => 100, 'minutes' => 300 } })
    end

    it 'shows a seller their calls and the missed ones of their state' do
      get "#{base}/crm/calls", headers: seller.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to match_array(Outsider::Voice::Call.where(linkedid: %w[mine missed-go]).ids)
    end

    it 'gives the seller a wallboard with only their own numbers, in their time zone' do
      started = Time.utc(2026, 10, 20, 13, 30)
      Outsider::Voice::Call.where(linkedid: 'mine').update_all(started_at: started, answered_at: started + 9.seconds) # rubocop:disable Rails/SkipsModelValidations
      travel_to Time.utc(2026, 10, 20, 18) do
        get "#{base}/crm/calls/wallboard", params: { period: 'today', user_id: colleague.id, zone: 'America/Sao_Paulo' },
                                           headers: seller.create_new_auth_token
      end

      body = response.parsed_body
      expect(body).to include('user_id' => seller.id, 'manager' => false, 'agents' => [])
      expect(body['summary']).to include('total' => 1, 'outbound' => 1, 'talk_seconds' => 120, 'longest_talk' => 120)
      expect(body['by_hour'][10]).to include('outbound' => 1)
      expect(body['by_weekday_hour'][2][10]).to eq(1)
      expect(body['goal']).to include('calls' => 100, 'minutes' => 300)
    end

    it 'gives the managers every seller, who is online and who is on a call now' do
      Outsider::Voice::CentralStatus.new(account).report(registration: 'Registered', extensions: ['202'])
      Outsider::Voice::Call.where(linkedid: 'mine').update_all(ended_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      get "#{base}/crm/calls/wallboard", params: { period: 'month' }, headers: admin.create_new_auth_token

      body = response.parsed_body
      expect(body['summary']).to include('total' => 3, 'inbound' => 1, 'missed' => 1)
      expect(body['agents'].find { |row| row['id'] == colleague.id }).to include('extension' => '202', 'online' => true, 'in_call' => true)
      expect(body['live'].pluck('user')).to eq([colleague.name])
    end

    it 'lists the calls to return' do
      get "#{base}/crm/calls", params: { to_return: 1 }, headers: colleague.create_new_auth_token

      expect(response.parsed_body['payload']).to be_empty
    end
  end
end
