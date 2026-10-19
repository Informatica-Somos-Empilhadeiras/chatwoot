require 'rails_helper'

RSpec.describe Outsider::Crm::Access do
  let(:account) { create(:account) }
  let(:locacao) { Outsider::Crm::BusinessUnit.create!(account: account, name: 'Locação') }
  let(:seminovos) { Outsider::Crm::BusinessUnit.create!(account: account, name: 'Seminovos') }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def access_for(user)
    described_class.new(account.account_users.find_by(user: user))
  end

  def opportunity_in(unit, owner: nil, contact: create(:contact, account: account))
    pipeline = Outsider::Crm::Pipeline.create!(account: account, business_unit: unit, name: 'P')
    Outsider::Crm::Opportunity.create!(
      account: account, business_unit: unit, pipeline: pipeline, contact: contact, owner: owner, title: 'Op',
      stage: Outsider::Crm::Stage.create!(account: account, pipeline: pipeline, name: 'S'),
      journey: Outsider::Crm::Journey.create!(account: account, contact: contact)
    )
  end

  before do
    locacao.members.create!(account: account, user: seller, role: :seller)
    locacao.members.create!(account: account, user: manager, role: :manager)
  end

  it 'keeps agents outside every unit out of the CRM' do
    expect(access_for(outsider)).not_to be_enabled
    expect(access_for(admin)).to be_enabled
  end

  it 'lets sellers see their unit and edit only their own opportunities' do
    own = opportunity_in(locacao, owner: seller)
    others = opportunity_in(seminovos)
    access = access_for(seller)

    expect(access.view_opportunity?(own)).to be(true)
    expect(access.edit_opportunity?(own)).to be(true)
    expect(access.view_opportunity?(others)).to be(false)
    expect(access.opportunities).to contain_exactly(own)
  end

  it 'lets managers edit every opportunity in their unit' do
    opportunity = opportunity_in(locacao, owner: seller)

    expect(access_for(manager).edit_opportunity?(opportunity)).to be(true)
    expect(access_for(seller).edit_opportunity?(opportunity_in(locacao, owner: manager))).to be(false)
  end

  it 'lets administrators see everything' do
    seminovos
    expect(access_for(admin).visible_unit_ids).to contain_exactly(locacao.id, seminovos.id)
  end
end
