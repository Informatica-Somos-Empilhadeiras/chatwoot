require 'rails_helper'

RSpec.describe Outsider::Crm::UpdatesChannel do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outsider) { create(:user, account: account, role: :agent) }

  before do
    stub_connection
    crm_enable(account)
  end

  def relay(message)
    subscription.send(:relay, message)
  end

  it 'streams the account CRM updates to people with CRM access' do
    subscribe(user_id: admin.id, pubsub_token: admin.pubsub_token, account_id: account.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("outsider_crm_#{account.id}")
    relay({ 'kind' => 'task', 'id' => 1 })
    expect(transmissions.last).to include('kind' => 'task', 'id' => 1)
  end

  it 'rejects wrong tokens and people from other accounts' do
    subscribe(user_id: admin.id, pubsub_token: 'wrong', account_id: account.id)
    expect(subscription).to be_rejected

    stranger = create(:user)
    subscribe(user_id: stranger.id, pubsub_token: stranger.pubsub_token, account_id: account.id)
    expect(subscription).to be_rejected
  end

  it 'sends only the access notice to people without CRM access, so the CRM shows up once it is turned on' do
    crm_enable(account, enabled: false)
    subscribe(user_id: admin.id, pubsub_token: admin.pubsub_token, account_id: account.id)
    expect(subscription).to be_confirmed

    relay({ 'kind' => 'opportunity', 'id' => 1 })
    crm_enable(account)
    relay({ 'kind' => 'access' })
    relay({ 'kind' => 'opportunity', 'id' => 2 })

    expect(transmissions.map { |message| [message['kind'], message['id']] }).to eq([['access', nil], ['opportunity', 2]])
  end

  it 'stops relaying updates to an agent whose CRM was turned off, except the access notice' do
    unit = crm_unit(account)
    Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: outsider, role: :seller)
    subscribe(user_id: outsider.id, pubsub_token: outsider.pubsub_token, account_id: account.id)

    relay({ 'kind' => 'task', 'id' => 1 })
    Outsider::Crm::Switch.new(account).update_agent(outsider.id, false)
    relay({ 'kind' => 'access', 'user_id' => outsider.id })
    relay({ 'kind' => 'task', 'id' => 2 })
    Outsider::Crm::Switch.new(account.reload).update_agent(outsider.id, true)
    relay({ 'kind' => 'access', 'user_id' => outsider.id })
    relay({ 'kind' => 'task', 'id' => 3 })

    sent = transmissions.map { |message| [message['kind'], message['id']] }
    expect(sent).to eq([['task', 1], ['access', nil], ['access', nil], ['task', 3]])
  end
end
