require 'rails_helper'

RSpec.describe Outsider::Voice::Settings do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:settings) { described_class.new(account) }
  let(:params) do
    { 'enabled' => true, 'ws_url' => 'wss://voz.exemplo.com.br/ws', 'public_ip' => '69.6.250.129', 'ring_seconds' => '20',
      'trunk' => { 'host' => 'sip.operadora.com.br', 'port' => '5060', 'auth' => 'register', 'username' => 'somos', 'password' => 'a;b' },
      'numbers' => [{ 'number' => '(62) 3234-5678', 'state' => 'GO', 'label' => 'Goiânia' }],
      'agents' => { seller.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true } } }
  end

  it 'keeps the operator password encrypted and never sends it back' do
    settings.update(params)

    stored = account.reload.internal_attributes['outsider_voice']['trunk']
    expect(stored['password_encrypted']).to be_present
    expect(stored.to_json).not_to include('a;b')
    expect(described_class.new(account).trunk['password']).to eq('a;b')
    expect(described_class.new(account).as_json['trunk']).to include('password_set' => true)
    expect(described_class.new(account).as_json['trunk']).not_to have_key('password_encrypted')
  end

  it 'keeps the password when the form leaves it blank' do
    settings.update(params)
    described_class.new(account).update(params.deep_merge('trunk' => { 'password' => '' }))

    expect(described_class.new(account).trunk['password']).to eq('a;b')
  end

  it 'lists every wrong field' do
    wrong = params.merge('ws_url' => 'http://x', 'numbers' => [{ 'number' => '123', 'state' => 'XX' }],
                         'agents' => { seller.id.to_s => { 'extension' => '600', 'enabled' => true } })

    expect { settings.update(wrong) }.to raise_error(described_class::Invalid) do |error|
      expect(error.errors).to include('ws_url', 'numbers.0.number', 'numbers.0.state', "agents.#{seller.id}.extension")
    end
  end

  it 'gives each extension its own password, stable while the extension stays the same' do
    settings.update(params)

    expect(settings.sip_password(seller.id, '201')).to eq(described_class.new(account).sip_password(seller.id, '201'))
    expect(settings.sip_password(seller.id, '201')).not_to eq(settings.sip_password(seller.id, '202'))
  end
end
