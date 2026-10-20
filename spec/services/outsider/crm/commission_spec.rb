require 'rails_helper'

RSpec.describe Outsider::Crm::Commission do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:other_unit) { crm_unit(account, name: 'Vendas') }
  let(:commission) { described_class.new(account) }

  it 'computes value x percent: R$ 1.000,00 at 1% pays R$ 10,00' do
    expect(described_class.amount(100_000, 100)).to eq(1_000)
    expect(described_class.amount(123_456, 150)).to eq(1_852)
  end

  it 'uses the most specific percent: seller and unit, seller, unit, then the general one' do
    config = commission.update(general_bp: 100, rules: [
                                 { user_id: seller.id, business_unit_id: unit.id, bp: 300 },
                                 { user_id: seller.id, bp: 200 },
                                 { business_unit_id: other_unit.id, bp: 150 }
                               ])

    expect(described_class.rate(config, seller.id, unit.id)).to eq(300)
    expect(described_class.rate(config, seller.id, other_unit.id)).to eq(200)
    expect(described_class.rate(config, other.id, other_unit.id)).to eq(150)
    expect(described_class.rate(config, other.id, unit.id)).to eq(100)
  end

  it 'applies a change from the current month on, keeping the percent of earlier months' do
    travel_to(Time.zone.local(2026, 9, 10)) { commission.update(general_bp: 100, rules: []) }
    travel_to(Time.zone.local(2026, 10, 5)) { commission.update(general_bp: 250, rules: []) }

    expect(commission.for_month('2026-09')['general_bp']).to eq(100)
    expect(commission.for_month('2026-10')).to include('from' => '2026-10', 'general_bp' => 250)
    expect(commission.for_month('2026-08')['general_bp']).to eq(0)
  end

  it 'refuses rules without a target, repeated rules and percents above 100%' do
    expect { commission.update(general_bp: 10_001, rules: [{ bp: 100 }, { user_id: seller.id, bp: 1 }, { user_id: seller.id, bp: 2 }]) }
      .to raise_error(Outsider::Crm::MonthlyConfig::Invalid) { |error| expect(error.errors).to eq(%w[general rules.0.target duplicate_rules]) }
  end
end
