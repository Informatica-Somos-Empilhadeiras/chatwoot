require 'rails_helper'

RSpec.describe Outsider::Crm::AutomationRules do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:proposal) { pipeline.stages.find_by(name: 'Proposta') }
  let(:rules) { described_class.new(account) }
  let(:task_rule) do
    { name: ' Tarefas da proposta ', trigger: 'stage_entered', wait_hours: 5,
      conditions: { pipeline_id: pipeline.id, stage_id: proposal.id, min_value_cents: '100000' },
      actions: [{ type: 'create_task', title: 'Enviar proposta', kind: 'proposal', due_in_hours: '24', assignee: 'owner', user_id: seller.id }] }
  end

  def errors_for(attributes)
    rules.create(attributes)
  rescue described_class::Invalid => e
    e.errors
  end

  it 'stores a cleaned rule: unit taken from the pipeline, wait only for timed triggers, user only for "user" tasks' do
    rule = rules.create(task_rule)

    expect(rule).to include('id' => 1, 'name' => 'Tarefas da proposta', 'active' => true, 'trigger' => 'stage_entered', 'wait_hours' => nil,
                            'conditions' => { 'business_unit_id' => unit.id, 'pipeline_id' => pipeline.id, 'stage_id' => proposal.id,
                                              'min_value_cents' => 100_000, 'lost_reason_id' => nil })
    expect(rule['actions']).to eq([{ 'type' => 'create_task', 'title' => 'Enviar proposta', 'kind' => 'proposal', 'description' => nil,
                                     'due_in_hours' => 24, 'assignee' => 'owner', 'user_id' => nil }])
    expect(account.reload.internal_attributes['outsider_crm_rules']).to eq([rule])
  end

  it 'returns field codes for what is missing or does not belong to the account' do
    other_pipeline = crm_pipeline(account, crm_unit(account, name: 'Seminovos'))
    expect(errors_for(name: '', trigger: 'nope', actions: [])).to contain_exactly('name_blank', 'trigger_invalid', 'actions_blank')
    expect(errors_for(name: 'x', trigger: 'stalled', wait_hours: 0, conditions: { business_unit_id: unit.id, pipeline_id: other_pipeline.id },
                      actions: [{ type: 'create_task', title: '' }, { type: 'add_label', label: 'nao-existe' }, { type: 'send_email' }]))
      .to contain_exactly('wait_hours', 'conditions.pipeline_id', 'actions.0.title_blank', 'actions.1.label', 'actions.2.type')
  end

  it 'only accepts open stages of the chosen pipeline and people of the account' do
    won = pipeline.stages.find_by(kind: :won)
    stranger = create(:user)

    expect(errors_for(name: 'x', trigger: 'created', conditions: { pipeline_id: pipeline.id, stage_id: won.id },
                      actions: [{ type: 'set_owner', user_id: stranger.id }])).to contain_exactly('conditions.stage_id', 'actions.0.user_id')
  end

  it 'never reuses an id, so the timeline of a deleted rule does not block a new one' do
    first = rules.create(task_rule)
    rules.destroy(first['id'])

    expect(rules.create(task_rule)['id']).to eq(2)
    expect(rules.all.size).to eq(1)
  end

  it 'turns a rule off without checking the rest again and validates any other change' do
    rule = rules.create(task_rule)
    proposal.update!(kind: :won)

    expect(rules.update(rule['id'], active: false)).to include('active' => false, 'name' => 'Tarefas da proposta')
    expect { rules.update(rule['id'], name: 'Outro') }.to raise_error(described_class::Invalid, 'conditions.stage_id')
    expect { rules.update(99, active: true) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'limits the number of rules per account' do
    stub_const("#{described_class}::MAX_RULES", 1)
    rules.create(task_rule)

    expect(errors_for(task_rule)).to eq(['too_many_rules'])
  end
end
