require 'rails_helper'

RSpec.describe Outsider::Voice::CallCosts do
  let(:account) { create(:account) }
  let(:settings) { Outsider::Voice::Settings.new(account) }
  let(:rates) do
    { 'local_fixed' => { 'minute' => '0,06' }, 'local_mobile' => { 'minute' => '0,20', 'call' => '0,05' },
      'long_fixed' => { 'minute' => '0,10' }, 'international' => { 'minute' => '1' }, 'inbound' => { 'call' => '0,01' } }
  end

  before { settings.update('costs' => { 'billing' => '30_6', 'rates' => rates }) }

  def build_call(attributes)
    Outsider::Voice::Call.new({ account_id: account.id, linkedid: SecureRandom.hex(4), direction: :outbound, status: :answered,
                                from_number: '+556232345678', started_at: Time.current, talk_seconds: 61 }.merge(attributes))
  end

  def costs
    described_class.new(Outsider::Voice::Settings.new(account))
  end

  it 'tells the kind of call by the area code of the line and the customer number' do
    expect(costs.kind(build_call(to_number: '+5562998100003'))).to eq('local_mobile')
    expect(costs.kind(build_call(to_number: '6232001122'))).to eq('local_fixed')
    expect(costs.kind(build_call(to_number: '1132001122'))).to eq('long_fixed')
    expect(costs.kind(build_call(to_number: '+15551234567'))).to eq('international')
    expect(costs.kind(build_call(to_number: '08001234567'))).to eq('special')
    expect(costs.kind(build_call(direction: :inbound, from_number: '+5511998100003', to_number: '6232345678'))).to eq('inbound')
    expect(costs.kind(build_call(direction: :internal, from_number: '201', to_number: '202'))).to be_nil
  end

  it 'charges the minimum of 30 seconds and then every 6 seconds, plus the price per call' do
    # 61 s => 30 + 36 = 66 s cobrados
    expect(costs.cost(build_call(to_number: '+5562998100003'))).to eq((0.05 + (0.20 * 66 / 60.0)).round(4))
    expect(costs.cost(build_call(to_number: '6232001122', talk_seconds: 10))).to eq((0.06 * 30 / 60.0).round(4))
  end

  it 'does not charge unanswered calls' do
    expect(costs.cost(build_call(to_number: '+5562998100003', status: :unanswered, talk_seconds: 0))).to eq(0.0)
  end

  it 'counts by second or by full minute when the carrier does' do
    settings.update(settings.as_json.deep_dup.merge('costs' => { 'billing' => 'minute', 'rates' => rates }))
    expect(costs.billed_seconds(61)).to eq(120)

    settings.update(settings.as_json.deep_dup.merge('costs' => { 'billing' => 'second', 'rates' => rates }))
    expect(costs.billed_seconds(61)).to eq(61)
  end
end
