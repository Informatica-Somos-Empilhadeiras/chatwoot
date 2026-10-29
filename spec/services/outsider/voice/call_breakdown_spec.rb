require 'rails_helper'

RSpec.describe Outsider::Voice::CallBreakdown do
  let(:account) { create(:account) }
  let(:calls) do
    [call('+5562998100003', seller), call('1132001122', seller), call('+15551234567', other),
     call('201', seller, direction: :internal, from_number: '202'), call('08001234567', other)]
  end
  let(:result) { described_class.new(Outsider::Voice::Settings.new(account), calls).to_h }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }

  before do
    settings.update(
      'costs' => { 'rates' => { 'local_mobile' => { 'call' => '1' }, 'long_fixed' => { 'call' => '2' }, 'international' => { 'call' => '5' } } },
      'branches' => [{ 'id' => 'goiania1', 'name' => 'Goiânia' }],
      'agents' => { seller.id.to_s => { 'extension' => '201', 'enabled' => true, 'branch' => 'goiania1' },
                    other.id.to_s => { 'extension' => '202', 'enabled' => true } }
    )
  end

  def call(to, user, attributes = {})
    Outsider::Voice::Call.create!({ account_id: account.id, linkedid: SecureRandom.hex(4), direction: :outbound, status: :answered,
                                    user_id: user.id, from_number: '6232345678', to_number: to, started_at: Time.current,
                                    talk_seconds: 60 }.merge(attributes))
  end

  it 'puts customer calls on the map by state, with the international ones apart' do
    expect(result[:regions][:states].keys).to contain_exactly('GO', 'SP')
    expect(result[:regions][:states]['GO']).to include(calls: 1, outbound: 1, answered: 1, cost: 1.0)
    expect(result[:regions][:international]).to include(calls: 1, cost: 5.0)
    expect(result[:regions][:unknown]).to eq(1)
  end

  it 'sums the costs of the period, leaving calls between extensions out' do
    expect(result[:costs]).to include(total: 8.0, outbound: 8.0, inbound: 0, configured: true, paid_calls: 3)
    expect(result[:costs][:by_kind].keys).to contain_exactly('local_mobile', 'long_fixed', 'international', 'special')
  end

  it 'groups by area code and by branch' do
    expect(result[:by_ddd].pluck(:ddd)).to contain_exactly('62', '11')
    expect(result[:by_branch]).to contain_exactly(include(id: 'goiania1', name: 'Goiânia', people: 1, calls: 2, cost: 3.0),
                                                  include(id: nil, calls: 2, cost: 5.0))
  end
end
