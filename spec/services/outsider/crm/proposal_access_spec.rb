require 'rails_helper'

RSpec.describe Outsider::Crm::ProposalAccess do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bia) { create(:user, account: account, role: :agent) }
  let(:caio) { create(:user, account: account, role: :agent) }
  let!(:ana_proposal) { crm_proposal(account, owner: ana) }
  let!(:bia_proposal) { crm_proposal(account, owner: bia) }
  let!(:caio_proposal) { crm_proposal(account, owner: caio) }
  let(:config) { Outsider::Crm::ProposalConfig.new(account) }

  def access_for(user)
    described_class.new(account.reload.account_users.find_by(user: user))
  end

  it 'shows agents only their own proposals by default and admins all of them' do
    expect(access_for(ana).proposals).to contain_exactly(ana_proposal)
    expect(access_for(admin).proposals).to contain_exactly(ana_proposal, bia_proposal, caio_proposal)
  end

  it 'adds the agents the admin chose' do
    config.update_access(ana.id, view: 'users', user_ids: [bia.id, ana.id])

    expect(access_for(ana).proposals).to contain_exactly(ana_proposal, bia_proposal)
    expect(access_for(ana).view?(caio_proposal)).to be(false)
  end

  it 'shows everything with "all" but still lets only the owner, creator or an admin edit' do
    config.update_access(ana.id, view: 'all')

    expect(access_for(ana).proposals.count).to eq(3)
    expect(access_for(ana).edit?(bia_proposal)).to be(false)
    expect(access_for(admin).edit?(bia_proposal)).to be(true)
  end

  it 'keeps proposals the agent created for someone else visible to them' do
    proposal = crm_proposal(account, owner: bia, created_by_id: ana.id)

    expect(access_for(ana).proposals).to include(proposal)
  end

  it 'lets agents manage the catalog only when allowed' do
    expect(access_for(ana).manage_catalog?).to be(false)
    config.update_access(ana.id, view: 'own', catalog: true)
    expect(access_for(ana).manage_catalog?).to be(true)
  end

  it 'deletes only drafts and locks the content of decided proposals' do
    access = access_for(ana)
    expect(access.delete?(ana_proposal)).to be(true)

    ana_proposal.update!(status: :accepted)
    expect(access.delete?(ana_proposal)).to be(false)
    expect(access.edit_content?(ana_proposal)).to be(false)
  end

  it 'rejects an unknown visibility' do
    expect { config.update_access(ana.id, view: 'everything') }.to raise_error(Outsider::Crm::ProposalConfig::Invalid)
  end
end
