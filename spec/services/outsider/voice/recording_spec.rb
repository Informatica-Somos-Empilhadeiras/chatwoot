require 'rails_helper'

RSpec.describe Outsider::Voice::Recording do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }
  let(:started) { Time.zone.parse('2026-10-27 14:00:00') }
  let(:file) { Rack::Test::UploadedFile.new(StringIO.new('webm'), 'audio/webm;codecs=opus', original_filename: 'ligacao.webm') }

  before do
    settings.update('enabled' => true, 'ws_url' => 'wss://voz.exemplo.com.br/ws', 'public_ip' => '69.6.250.129',
                    'agents' => { seller.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true } })
  end

  def create_call(linkedid, attributes)
    Outsider::Voice::Call.create!({ account_id: account.id, linkedid: linkedid, status: :answered, started_at: started }.merge(attributes))
  end

  it 'keeps the recording on the customer call, even in a conference with a colleague' do
    customer = create_call('cliente', direction: :inbound, user_id: seller.id, from_number: '+5562998100003', to_number: '6232345678')
    create_call('colega', direction: :internal, user_id: create(:user, account: account).id, from_number: '201', to_number: '202')
    parties = [{ 'number' => '5562998100003', 'started_at' => (started + 3.seconds).iso8601 },
               { 'number' => '202', 'started_at' => (started + 40.seconds).iso8601 }]

    call = described_class.new(Outsider::Voice::Settings.new(account), seller).attach(file: file, parties: parties)

    expect(call).to eq(customer)
    expect(customer.reload.recording).to be_attached
  end

  it 'does not attach to a call of someone else' do
    create_call('outro', direction: :inbound, user_id: create(:user, account: account).id, from_number: '+5562998100003',
                         to_number: '6232345678')
    parties = [{ 'number' => '5562998100003', 'started_at' => started.iso8601 }]

    expect(described_class.new(Outsider::Voice::Settings.new(account), seller).attach(file: file, parties: parties)).to be_nil
  end

  it 'ignores parties without a valid time' do
    parties = [{ 'number' => '5562998100003', 'started_at' => 'ontem' }]

    expect(described_class.new(Outsider::Voice::Settings.new(account), seller).attach(file: file, parties: parties)).to be_nil
  end
end
