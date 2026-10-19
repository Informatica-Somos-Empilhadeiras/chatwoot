require 'rails_helper'

RSpec.describe Outsider::Crm::Opportunity do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:stage) { pipeline.first_open_stage }
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
    other = crm_opportunity(other_account, crm_unit(other_account))

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
    opportunity = build_opportunity(contact: create(:contact))

    expect(opportunity).not_to be_valid
    expect(opportunity.errors[:contact]).to be_present
  end

  it 'rejects a stage from another pipeline' do
    other_stage = crm_pipeline(account, unit, name: 'Outro').first_open_stage

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

  describe 'status and stage' do
    let(:opportunity) { build_opportunity.tap(&:save!) }

    it 'closes as won when moved to the won stage' do
      opportunity.update!(stage: pipeline.stages.find_by(kind: :won))

      expect(opportunity).to be_won
      expect(opportunity.closed_at).to be_present
    end

    it 'moves to the lost stage when marked as lost and reopens at the first stage' do
      opportunity.update!(status: :lost)
      expect(opportunity.stage.name).to eq('Perdido')

      opportunity.update!(status: :open)
      expect(opportunity.stage).to eq(stage)
      expect(opportunity.closed_at).to be_nil
    end

    it 'requires a reason to lose once the account has reasons' do
      reason = Outsider::Crm::LostReason.create!(account: account, name: 'Preço')

      expect(opportunity.update(status: :lost)).to be(false)
      expect(opportunity.update(status: :lost, lost_reason: reason)).to be(true)
    end

    it 'logs creation, stage and status changes in the timeline' do
      Current.user = create(:user, account: account)
      opportunity.update!(stage: pipeline.stages.second)
      opportunity.update!(status: :won)

      expect(opportunity.activities.pluck(:kind)).to eq(%w[created stage_changed stage_changed status_changed])
      expect(opportunity.activities.second.metadata).to eq('from' => 'Qualificação', 'to' => 'Proposta')
      expect(opportunity.activities.last.user).to eq(Current.user)
    ensure
      Current.reset
    end
  end

  describe 'custom fields' do
    before do
      Outsider::Crm::CustomFieldDefinition.create!(account: account, key: 'cnpj', label: 'CNPJ', required: true)
      Outsider::Crm::CustomFieldDefinition.create!(account: account, key: 'frota', label: 'Frota', field_type: :number)
      Outsider::Crm::CustomFieldDefinition.create!(account: account, key: 'tipo', label: 'Tipo', field_type: :list, options: %w[Locação Venda])
    end

    it 'accepts known fields with valid values' do
      expect(build_opportunity(custom_fields: { 'cnpj' => '28.491.022/0001-90', 'frota' => 3, 'tipo' => 'Venda' })).to be_valid
    end

    it 'rejects missing required, unknown and badly typed fields' do
      expect(build_opportunity(custom_fields: {})).not_to be_valid
      expect(build_opportunity(custom_fields: { 'cnpj' => 'x', 'outro' => 1 })).not_to be_valid
      expect(build_opportunity(custom_fields: { 'cnpj' => 'x', 'frota' => 'muitas' })).not_to be_valid
      expect(build_opportunity(custom_fields: { 'cnpj' => 'x', 'tipo' => 'Aluguel' })).not_to be_valid
    end
  end
end
