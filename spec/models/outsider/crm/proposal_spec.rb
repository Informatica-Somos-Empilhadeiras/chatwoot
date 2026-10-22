require 'rails_helper'

RSpec.describe Outsider::Crm::Proposal do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  describe 'numbering' do
    it 'continues from the next number set in the settings and never repeats' do
      Outsider::Crm::ProposalConfig.new(account).update_general(next_number: 2597)

      first = crm_proposal(account, owner: user)
      second = crm_proposal(account, owner: user, kind: :rental)

      expect([first.number, second.number]).to eq([2597, 2598])
      expect(first.code).to eq('PROPOSTA 2597')
    end

    it 'keeps counting from the last proposal when the setting is lower' do
      crm_proposal(account, owner: user)
      Outsider::Crm::ProposalConfig.new(account.reload).update_general(next_number: 1)

      expect(crm_proposal(account, owner: user).number).to eq(2)
    end

    it 'numbers each account on its own' do
      other = create(:account)
      other_user = create(:user, account: other, role: :administrator)

      expect(crm_proposal(account, owner: user).number).to eq(1)
      expect(crm_proposal(other, owner: other_user).number).to eq(1)
    end
  end

  it 'adds up the items, discounting each one' do
    proposal = crm_proposal(account, owner: user, items: [
                              { description: 'Máquina', quantity: 2, unit_price_cents: 10_000, discount_cents: 1_500 },
                              { description: 'Garfo', quantity: 1.5, unit_price_cents: 1_000 }
                            ])

    expect(proposal.items.map(&:total_cents)).to eq([18_500, 1_500])
    expect(proposal.total_cents).to eq(20_000)
  end

  it 'refuses a discount above the item value' do
    expect do
      crm_proposal(account, owner: user, items: [{ description: 'Máquina', quantity: 1, unit_price_cents: 100, discount_cents: 200 }])
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'refuses a template of the other kind' do
    proposal = crm_proposal(account, owner: user)
    proposal.template = Outsider::Crm::ProposalTemplate.find_by(account_id: account.id, kind: :rental)

    expect(proposal).not_to be_valid
    expect(proposal.errors[:template]).to be_present
  end

  it 'refuses a deal of another contact' do
    unit = crm_unit(account)
    proposal = crm_proposal(account, owner: user)
    proposal.opportunity = crm_opportunity(account, unit)

    expect(proposal).not_to be_valid
    expect(proposal.errors[:opportunity]).to be_present
  end

  it 'refuses a WhatsApp group as the customer' do
    group = create(:contact, account: account, identifier: '1203630@g.us')

    expect { crm_proposal(account, owner: user, contact: group) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'shows open proposals past their validity as expired' do
    proposal = crm_proposal(account, owner: user, valid_until: Time.zone.yesterday)
    expect(proposal.display_status).to eq('expired')

    proposal.update!(status: :accepted)
    expect(proposal.display_status).to eq('accepted')
  end

  it 'keeps only the known customer fields and drops blank conditions' do
    proposal = crm_proposal(account, owner: user, customer: { 'company' => ' ACME ', 'hack' => 'x' },
                                     conditions: [{ 'label' => 'Frete', 'text' => 'FOB' }, { 'label' => '', 'text' => '' }])

    expect(proposal.customer).to include('company' => 'ACME')
    expect(proposal.customer).not_to have_key('hack')
    expect(proposal.conditions).to eq([{ 'label' => 'Frete', 'text' => 'FOB' }])
  end

  it 'nullifies the link when the deal is deleted and keeps the proposal' do
    unit = crm_unit(account)
    opportunity = crm_opportunity(account, unit)
    proposal = crm_proposal(account, owner: user, contact: opportunity.contact, opportunity: opportunity)

    opportunity.destroy!

    expect(proposal.reload.opportunity_id).to be_nil
  end
end
