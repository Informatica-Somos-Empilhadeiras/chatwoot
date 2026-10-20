require 'rails_helper'

RSpec.describe Outsider::Crm::RuleRunner do
  # regra "quando perder, encaminhe para outra unidade"
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:receiver) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:other_unit) { crm_unit(account, name: 'Vendas') }
  let(:pipeline) { crm_pipeline(account, unit) }
  let!(:other_pipeline) { crm_pipeline(account, other_unit, name: 'Novos') }
  let(:rules) { Outsider::Crm::AutomationRules.new(account) }
  let(:no_budget) { Outsider::Crm::LostReason.create!(account: account, name: 'Sem verba', kind: :lost) }
  let(:wrong_unit) { Outsider::Crm::LostReason.create!(account: account, name: 'Unidade errada', kind: :both) }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    other_unit.members.create!(account: account, user: receiver, role: :seller)
  end

  def deal(**attrs)
    crm_opportunity(account, unit, pipeline: pipeline, owner: seller, **attrs)
  end

  def forward_rule(action = {}, conditions: {})
    rules.create(name: 'Perdido vai para Vendas', trigger: 'lost', conditions: conditions,
                 actions: [{ type: 'forward', to_business_unit_id: other_unit.id, owner_id: receiver.id, create_task: true }.merge(action)])
  end

  def lose(opportunity, reason = wrong_unit)
    opportunity.update!(status: :lost, lost_reason: reason)
    opportunity.reload
  end

  def summary(opportunity)
    opportunity.activities.automation.order(:id).last&.metadata
  end

  it 'forwards the lost deal to the destination unit, using the lost reason when it also serves forwarding' do
    forward_rule({ notes: 'Cliente quer comprar, não alugar' })
    origin = lose(deal(value_cents: 80_000))

    target = origin.outgoing_forward.to_opportunity
    expect(origin.status).to eq('forwarded')
    expect(target).to have_attributes(business_unit_id: other_unit.id, pipeline_id: other_pipeline.id, owner_id: receiver.id,
                                      status: 'open', value_cents: 80_000, journey_id: origin.journey_id)
    expect(target.tasks.pending.pluck(:assignee_id, :kind)).to eq([[receiver.id, 'call']])
    forward = Outsider::Crm::Forward.last
    expect(forward).to have_attributes(reason_id: wrong_unit.id, requested_by_id: nil, notes: 'Cliente quer comprar, não alugar')
    expect(target.activities.received.last.metadata).to include('rule' => 'Perdido vai para Vendas', 'from_unit' => 'Locação')
    expect(summary(origin)).to include('forwarded' => { 'unit' => 'Vendas', 'code' => target.code })
  end

  it 'only runs for the chosen lost reason' do
    forward_rule(conditions: { lost_reason_id: wrong_unit.id })
    kept = lose(deal, no_budget)
    moved = lose(deal(contact: create(:contact, account: account)), wrong_unit)

    expect(kept.status).to eq('lost')
    expect(moved.status).to eq('forwarded')
  end

  it 'keeps the deal lost and records why when the forward is refused' do
    forward_rule
    origin = deal
    crm_opportunity(account, other_unit, pipeline: other_pipeline, contact: origin.contact)

    lost = lose(origin)

    expect(lost.status).to eq('lost')
    expect(summary(lost)).to include('forward_error' => 'duplicate_open')
  end

  it 'ignores deals already in the destination unit' do
    forward_rule
    origin = crm_opportunity(account, other_unit, pipeline: other_pipeline)

    lost = lose(origin)

    expect(lost.status).to eq('lost')
    expect(summary(lost)).to include('skipped' => ['same_unit'])
  end

  describe 'validation' do
    def errors_for(trigger, action)
      rules.create(name: 'x', trigger: trigger, actions: [{ type: 'forward' }.merge(action)])
      []
    rescue Outsider::Crm::AutomationRules::Invalid => e
      e.errors
    end

    it 'accepts forward only on the lost trigger, to an active unit' do
      expect(errors_for('won', to_business_unit_id: other_unit.id)).to include('actions.0.forward_trigger')
      expect(errors_for('lost', {})).to eq(['actions.0.to_business_unit_id'])
      expect(errors_for('lost', to_business_unit_id: other_unit.id)).to eq([])
    end

    it 'requires a destination member as owner and a forwarding reason' do
      expect(errors_for('lost', to_business_unit_id: other_unit.id, owner_id: seller.id)).to eq(['actions.0.owner_id'])
      expect(errors_for('lost', to_business_unit_id: other_unit.id, reason_id: no_budget.id)).to eq(['actions.0.reason_id'])
    end

    it 'drops the lost reason condition on other triggers' do
      rule = rules.create(name: 'x', trigger: 'won', conditions: { lost_reason_id: no_budget.id }, actions: [{ type: 'add_note', body: 'a' }])
      expect(rule['conditions']['lost_reason_id']).to be_nil
    end
  end
end
