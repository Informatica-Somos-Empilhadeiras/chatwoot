require 'rails_helper'

RSpec.describe Outsider::Crm::UpdatesChannel do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outsider) { create(:user, account: account, role: :agent) }

  before { stub_connection }

  it 'streams the account CRM updates to people with CRM access' do
    subscribe(user_id: admin.id, pubsub_token: admin.pubsub_token, account_id: account.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("outsider_crm_#{account.id}")
  end

  it 'rejects agents outside the CRM units and wrong tokens' do
    subscribe(user_id: outsider.id, pubsub_token: outsider.pubsub_token, account_id: account.id)
    expect(subscription).to be_rejected

    subscribe(user_id: admin.id, pubsub_token: 'wrong', account_id: account.id)
    expect(subscription).to be_rejected
  end
end
