require 'rails_helper'

RSpec.describe 'Outsider CRM proposal reports', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:product) do
    Outsider::Crm::Product.create!(account: account, kind: :machine, name: 'HELI CPCD35', sale_price_cents: 10_000_000)
  end

  before { [seller, other].each { |user| unit.members.create!(account: account, user: user, role: :seller) } }

  def report(user, **params)
    get "/api/v1/accounts/#{account.id}/outsider/crm/proposal_reports", headers: user.create_new_auth_token, params: params, as: :json
    response.parsed_body
  end

  def item(quantity: 1)
    [{ description: 'HELI CPCD35', quantity: quantity, unit_price_cents: 10_000_000, product_id: product.id },
     { description: 'Frete', quantity: 1, unit_price_cents: 50_000 }]
  end

  it 'counts the proposals issued in the period by current situation, only those the person can see' do
    crm_proposal(account, owner: seller, items: item(quantity: 2), status: :accepted, sent_at: 4.days.ago, decided_at: 2.days.ago)
    crm_proposal(account, owner: seller, items: item, status: :rejected, sent_at: 3.days.ago, decided_at: 2.days.ago)
    crm_proposal(account, owner: seller, items: item, status: :sent, sent_at: 1.day.ago, valid_until: Time.zone.today - 1)
    crm_proposal(account, owner: seller, status: :sent, sent_at: 1.day.ago)
    crm_proposal(account, owner: seller, status: :canceled)
    crm_proposal(account, owner: other)
    crm_proposal(account, owner: seller, issued_on: 3.months.ago.to_date)

    body = report(seller, period: 'month')
    expect(body['summary']).to include(
      'issued_count' => 4, 'accepted_count' => 1, 'rejected_count' => 1, 'expired_count' => 1, 'open_count' => 1,
      'canceled_count' => 1, 'draft_count' => 0, 'acceptance_rate' => 33.3, 'average_days_to_decision' => 1.5,
      'accepted_value_cents' => 20_050_000, 'sent_count' => 4
    )
    expect(body['owners'].pluck('name')).to eq([seller.name])
    heli = body['products'].first
    expect(heli).to include('product_id' => product.id, 'name' => 'HELI CPCD35', 'quantity' => 4.0, 'proposals_count' => 3,
                            'accepted_quantity' => 2.0, 'accepted_value_cents' => 20_000_000)

    expect(report(admin, period: 'month')['summary']['issued_count']).to eq(5)
    expect(report(admin, period: 'month', owner_id: other.id)['summary']['issued_count']).to eq(1)
  end

  it 'filters by unit, using the deal unit when the proposal has none' do
    other_unit = crm_unit(account, name: 'Vendas')
    deal = crm_opportunity(account, other_unit, owner: seller)
    crm_proposal(account, owner: seller, contact: deal.contact, opportunity: deal)
    crm_proposal(account, owner: seller, business_unit: unit)
    crm_proposal(account, owner: seller)

    expect(report(admin, business_unit_id: other_unit.id)['summary']['issued_count']).to eq(1)
    expect(report(admin, business_unit_id: unit.id)['summary']['issued_count']).to eq(1)
  end
end
