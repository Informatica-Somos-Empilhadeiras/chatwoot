require 'rails_helper'

RSpec.describe 'Outsider CRM received forwards API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:sender) { create(:user, account: account, role: :agent) }
  let(:receiver) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:origin_unit) { crm_unit(account) }
  let(:unit) { crm_unit(account, name: 'Vendas') }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/received_forwards" }

  before do
    crm_pipeline(account, unit)
    origin_unit.members.create!(account: account, user: sender, role: :seller)
    unit.members.create!(account: account, user: receiver, role: :seller)
    unit.members.create!(account: account, user: manager, role: :manager)
  end

  def forward(owner: receiver)
    origin = crm_opportunity(account, origin_unit, owner: sender, title: 'Empilhadeira')
    access = Outsider::Crm::Access.new(AccountUser.find_by(account: account, user: sender))
    params = { to_business_unit_id: unit.id, owner_id: owner&.id, notes: 'Quer comprar' }
    Outsider::Crm::OpportunityForwarder.new(origin, access: access, user: sender, params: params).perform.to_opportunity
  end

  def items(user)
    get url, headers: user.create_new_auth_token, as: :json
    response.parsed_body['payload']
  end

  it 'notifies the owner in the destination, never the person who forwarded' do
    target = forward

    expect(items(receiver).map { |item| item.slice('opportunity_id', 'from_unit', 'by', 'notes', 'notified') })
      .to eq([{ 'opportunity_id' => target.id, 'from_unit' => 'Locação', 'by' => sender.name, 'notes' => 'Quer comprar', 'notified' => false }])
    expect(items(manager)).to be_empty
    expect(items(sender)).to be_empty
  end

  it 'notifies the unit managers when the deal arrives without an owner' do
    target = forward(owner: nil)

    expect(items(manager).pluck('opportunity_id')).to eq([target.id])
    expect(items(receiver)).to be_empty
    expect(items(admin)).to be_empty
  end

  it 'keeps the dot after the notice is closed and clears it when the deal is opened' do
    target = forward

    post "#{url}/mark", params: { opportunity_ids: [target.id], opened: false }, headers: receiver.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('notified')).to eq([true])

    post "#{url}/mark", params: { opportunity_ids: [target.id], opened: true }, headers: receiver.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to be_empty
    expect(target.activities.received.last.metadata).to include('notified' => [receiver.id], 'opened' => [receiver.id])
  end

  it 'stops notifying once the deal is closed' do
    target = forward
    target.update!(status: :won)

    expect(items(receiver)).to be_empty
  end
end
