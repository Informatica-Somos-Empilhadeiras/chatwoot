require 'rails_helper'

RSpec.describe Outsider::Crm::Goals do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:goals) { described_class.new(account) }

  it 'keeps a goal for the month it was saved and the following ones, until the next change' do
    goals.update('2026-09', units: { unit.id.to_s => '5000000' }, users: { seller.id.to_s => '1000000' })
    goals.update('2026-11', units: { unit.id.to_s => '8000000' }, users: {})

    expect(goals.for_month('2026-08')).to include('from' => nil, 'units' => {}, 'users' => {})
    expect(goals.for_month('2026-10')).to include('from' => '2026-09', 'units' => { unit.id.to_s => 5_000_000 },
                                                  'users' => { seller.id.to_s => 1_000_000 })
    expect(goals.for_month('2027-01')).to include('from' => '2026-11', 'units' => { unit.id.to_s => 8_000_000 }, 'users' => {})
  end

  it 'ignores empty goals and refuses units or people from outside the account' do
    stranger = create(:user)
    expect(goals.update('2026-10', units: { unit.id.to_s => '' }, users: { seller.id.to_s => '0' })['units']).to eq({})
    expect { goals.update('2026-10', units: {}, users: { stranger.id.to_s => '100' }) }
      .to raise_error(Outsider::Crm::MonthlyConfig::Invalid) { |error| expect(error.errors).to eq(["users.#{stranger.id}"]) }
    expect { goals.update('2026-13', units: {}, users: {}) }.to raise_error(Outsider::Crm::MonthlyConfig::Invalid)
  end
end
