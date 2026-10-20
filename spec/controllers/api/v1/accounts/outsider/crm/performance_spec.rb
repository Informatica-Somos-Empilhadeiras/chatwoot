require 'rails_helper'

RSpec.describe 'Outsider CRM goals, commission and seller-only numbers', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:colleague) { create(:user, account: account, role: :agent, name: 'Caio') }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/crm" }
  let(:month) { Time.zone.today.strftime('%Y-%m') }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
    unit.members.create!(account: account, user: manager, role: :manager)
    won(seller, 100_000)
    won(colleague, 300_000)
    crm_opportunity(account, unit, pipeline: pipeline, owner: colleague, value_cents: 50_000)
    Outsider::Crm::Goals.new(account).update(month, units: { unit.id.to_s => '1000000' }, users: { seller.id.to_s => '400000' })
    Outsider::Crm::Commission.new(account).update(general_bp: 100, rules: [{ user_id: colleague.id, bp: 200 }])
  end

  def won(owner, cents)
    crm_opportunity(account, unit, pipeline: pipeline, owner: owner, value_cents: cents).tap { |deal| deal.update!(status: :won) }
  end

  def get_json(user, path, params = {})
    get "#{base}/#{path}", params: params, headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'shows the seller only their own month, goal and commission, deal by deal' do
    data = get_json(seller, 'performance', month: month)

    expect(data).to include('manager' => false, 'units' => [], 'sellers' => [])
    expect(data['me']).to include('won_cents' => 100_000, 'goal_cents' => 400_000, 'commission_cents' => 1_000)
    expect(data['me']['deals'].map { |deal| deal.slice('value_cents', 'bp', 'commission_cents') })
      .to eq([{ 'value_cents' => 100_000, 'bp' => 100, 'commission_cents' => 1_000 }])
  end

  it 'shows managers every unit and seller with goals and commissions' do
    data = get_json(manager, 'performance', month: month)

    expect(data['me']).to be_nil
    expect(data['units']).to eq([{ 'id' => unit.id, 'name' => 'Locação', 'won_cents' => 400_000, 'won_count' => 2, 'goal_cents' => 1_000_000 }])
    expect(data['sellers'].map { |row| row.slice('name', 'won_cents', 'goal_cents', 'commission_cents') })
      .to eq([{ 'name' => 'Caio', 'won_cents' => 300_000, 'goal_cents' => nil, 'commission_cents' => 6_000 },
              { 'name' => 'Bia', 'won_cents' => 100_000, 'goal_cents' => 400_000, 'commission_cents' => 1_000 },
              { 'name' => manager.name, 'won_cents' => 0, 'goal_cents' => nil, 'commission_cents' => 0 }])
    expect(data['totals']).to include('won_cents' => 400_000, 'goal_cents' => 1_000_000, 'commission_cents' => 7_000)
  end

  it 'counts only the seller deals in the top indicators and reports' do
    expect(get_json(seller, 'opportunities/summary')).to include('won_value_cents' => 100_000, 'open_count' => 0)
    expect(get_json(manager, 'opportunities/summary')).to include('won_value_cents' => 400_000, 'open_count' => 1)
    expect(get_json(seller, 'reports')['owners'].pluck('id')).to eq([seller.id])
  end

  it 'hides colleagues deals from sellers when the account turns on "sellers see own deals"' do
    expect(get_json(seller, 'opportunities')['meta']['count']).to eq(3)
    Outsider::Crm::Settings.new(account).update(sellers_see_own_deals: true)
    unowned = crm_opportunity(account, unit, pipeline: pipeline)

    ids = get_json(seller, 'opportunities')['payload'].pluck('id')
    expect(ids).to include(unowned.id)
    expect(Outsider::Crm::Opportunity.where(id: ids).pluck(:owner_id).uniq).to contain_exactly(seller.id, nil)
    expect(get_json(manager, 'opportunities')['meta']['count']).to eq(4)
  end

  it 'lets only administrators read and change goals and commission' do
    put "#{base}/commission", params: { general_bp: 150, rules: [] }, headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    put "#{base}/goals", params: { month: month, units: { unit.id => 2_000_000 }, users: {} }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('units' => { unit.id.to_s => 2_000_000 })
    expect(response.parsed_body['people'].pluck('name')).to include('Bia', 'Caio', admin.name)
  end
end
