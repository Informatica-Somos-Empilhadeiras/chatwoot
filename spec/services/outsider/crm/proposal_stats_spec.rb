require 'rails_helper'

RSpec.describe Outsider::Crm::ProposalStats do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:unit) { crm_unit(account) }
  let(:deal) { crm_opportunity(account, unit, owner: seller) }

  def access(user)
    Outsider::Crm::Access.new(account.account_users.find_by(user: user))
  end

  before { [seller, other].each { |user| unit.members.create!(account: account, user: user, role: :seller) } }

  it 'summarizes the latest visible proposal of each deal, ignoring canceled ones' do
    older = travel_to(2.days.ago) { crm_proposal(account, owner: seller, contact: deal.contact, opportunity: deal) }
    older.update!(status: :sent, sent_at: 1.day.ago, valid_until: Time.zone.today - 1)
    crm_proposal(account, owner: seller, contact: deal.contact, opportunity: deal, status: :canceled)
    crm_proposal(account, owner: other, contact: deal.contact, opportunity: deal)

    mine = described_class.for([deal.id], access(seller))[deal.id]
    expect(mine).to include(id: older.id, number: older.number, status: 'expired', count: 1)
    expect(described_class.for([deal.id], access(admin))[deal.id]).to include(count: 2, status: 'draft')
    expect(described_class.for([deal.id], nil)).to eq({})

    row = Outsider::Crm::Serializer.opportunities([deal], access: access(seller)).first
    expect(row[:proposal]).to include(id: older.id)
    other_deal = crm_opportunity(account, unit, owner: seller)
    expect(Outsider::Crm::Serializer.opportunities([other_deal], access: access(seller)).first[:proposal]).to be_nil
  end
end
