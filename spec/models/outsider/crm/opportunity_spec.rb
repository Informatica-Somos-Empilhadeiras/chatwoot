require 'rails_helper'

RSpec.describe Outsider::Crm::Opportunity do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:unit) { Outsider::Crm::BusinessUnit.create!(account: account, name: 'Locação') }
  let(:pipeline) { Outsider::Crm::Pipeline.create!(account: account, business_unit: unit, name: 'Vendas') }
  let(:stage) { Outsider::Crm::Stage.create!(account: account, pipeline: pipeline, name: 'Qualificação', probability: 30) }
  let(:journey) { Outsider::Crm::Journey.create!(account: account, contact: contact) }

  def build_opportunity(**attrs)
    described_class.new({ account: account, journey: journey, business_unit: unit, pipeline: pipeline, stage: stage,
                          contact: contact, title: 'Renovação' }.merge(attrs))
  end

  it 'numbers opportunities per account' do
    first = build_opportunity.tap(&:save!)
    first.update!(status: :won)
    second = build_opportunity.tap(&:save!)
    other_account = create(:account)
    other_unit = Outsider::Crm::BusinessUnit.create!(account: other_account, name: 'Outra')
    other_pipeline = Outsider::Crm::Pipeline.create!(account: other_account, business_unit: other_unit, name: 'P')
    other_contact = create(:contact, account: other_account)
    other = described_class.create!(
      account: other_account, business_unit: other_unit, pipeline: other_pipeline, contact: other_contact, title: 'X',
      journey: Outsider::Crm::Journey.create!(account: other_account, contact: other_contact),
      stage: Outsider::Crm::Stage.create!(account: other_account, pipeline: other_pipeline, name: 'S')
    )

    expect([first.display_id, second.display_id, other.display_id]).to eq([1, 2, 1])
    expect(second.code).to eq('OP-2')
  end

  it 'allows only one open opportunity per contact and unit' do
    build_opportunity.save!
    duplicate = build_opportunity

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:base]).to be_present
  end

  it 'rejects a contact from another account' do
    foreign_contact = create(:contact)
    opportunity = build_opportunity(contact: foreign_contact)

    expect(opportunity).not_to be_valid
    expect(opportunity.errors[:contact]).to be_present
  end

  it 'rejects a stage from another pipeline' do
    other_pipeline = Outsider::Crm::Pipeline.create!(account: account, business_unit: unit, name: 'Outro')
    other_stage = Outsider::Crm::Stage.create!(account: account, pipeline: other_pipeline, name: 'S')

    expect(build_opportunity(stage: other_stage)).not_to be_valid
  end

  it 'rejects an owner who is not in the account' do
    expect(build_opportunity(owner: create(:user))).not_to be_valid
    expect(build_opportunity(owner: create(:user, account: account))).to be_valid
  end

  it 'uses the stage probability when none is set' do
    expect(build_opportunity.effective_probability).to eq(30)
    expect(build_opportunity(probability: 80).effective_probability).to eq(80)
  end

  it 'records changes in the audit log' do
    opportunity = build_opportunity.tap(&:save!)
    opportunity.update!(value_cents: 6_800_000)

    expect(opportunity.audits.last.audited_changes).to include('value_cents' => [0, 6_800_000])
  end
end
