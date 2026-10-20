require 'rails_helper'

RSpec.describe Outsider::Crm::RuleRunner do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:proposal) { pipeline.stages.find_by(name: 'Proposta') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:rules) { Outsider::Crm::AutomationRules.new(account) }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: manager, role: :manager)
    create(:label, account: account, title: 'proposta')
  end

  def deal(contact: create(:contact, account: account), **attrs)
    crm_opportunity(account, unit, pipeline: pipeline, contact: contact, owner: seller, **attrs)
  end

  def rule(trigger, actions, **attrs)
    rules.create({ name: "Regra #{trigger}", trigger: trigger, actions: actions }.merge(attrs))
  end

  def entries(opportunity)
    opportunity.activities.automation.order(:id).map(&:metadata)
  end

  it 'creates the stage template tasks when a deal enters the stage, for the owner and the unit managers' do
    rule('stage_entered', [{ type: 'create_task', title: 'Enviar proposta', kind: 'proposal', due_in_hours: 24 },
                           { type: 'create_task', title: 'Revisar desconto', assignee: 'managers' }],
         conditions: { pipeline_id: pipeline.id, stage_id: proposal.id })
    opportunity = deal
    expect(opportunity.tasks).to be_empty

    opportunity.update!(stage: proposal)

    tasks = opportunity.tasks.order(:id)
    expect(tasks.map { |task| [task.title, task.kind, task.assignee_id, task.created_by_id] })
      .to eq([['Enviar proposta', 'proposal', seller.id, nil], ['Revisar desconto', 'follow_up', manager.id, nil]])
    expect(tasks.first.due_at).to be_within(1.minute).of(24.hours.from_now)
    expect(entries(opportunity)).to eq([{ 'rule' => 'custom', 'rule_id' => 1, 'rule_name' => 'Regra stage_entered', 'tasks' => 2 }])
  end

  it 'runs "created" and "stage_entered" rules when the deal is created and skips deals outside the conditions' do
    rule('created', [{ type: 'add_note', body: 'Conferir cadastro' }], conditions: { min_value_cents: 50_000 })
    rule('stage_entered', [{ type: 'add_label', label: 'proposta' }])

    small = deal(value_cents: 10_000)
    big = deal(value_cents: 90_000, contact: contact, conversation: conversation)

    expect(small.activities.note).to be_empty
    expect(big.activities.note.pluck(:body, :user_id)).to eq([['Conferir cadastro', nil]])
    expect(conversation.reload.label_list).to eq(['proposta'])
    expect(entries(small)).to eq([{ 'rule' => 'custom', 'rule_id' => 2, 'rule_name' => 'Regra stage_entered', 'skipped' => ['no_conversation'] }])
  end

  it 'runs won rules after the closing automations, so their tasks stay pending' do
    Outsider::Crm::Settings.new(account).update(automation_close_tasks: true)
    rule('won', [{ type: 'create_task', title: 'Agendar entrega', assignee: 'user', user_id: manager.id }])
    rule('lost', [{ type: 'add_note', body: 'Perdido' }])
    opportunity = deal
    opportunity.tasks.create!(account: account, title: 'Ligar')

    opportunity.update!(status: :won)

    expect(opportunity.tasks.pending.pluck(:title, :assignee_id)).to eq([['Agendar entrega', manager.id]])
    expect(entries(opportunity).pluck('rule')).to eq(%w[close_tasks custom])
  end

  it 'passes the deal only to someone who can own it in the unit' do
    rule('created', [{ type: 'set_owner', user_id: manager.id }])
    expect(deal.reload.owner_id).to eq(manager.id)

    rules.update(1, active: false)
    rule('created', [{ type: 'set_owner', user_id: outsider.id }])
    opportunity = deal
    expect(opportunity.reload.owner_id).to eq(seller.id)
    expect(entries(opportunity).last).to include('skipped' => ['owner_not_member'])
  end

  it 'leaves inactive rules alone and never breaks the save of the deal when a rule fails' do
    rule('created', [{ type: 'add_note', body: 'x' }], active: false)
    rule('created', [{ type: 'create_task', title: 'Ligar' }])
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    allow(Outsider::Crm::Automations).to receive(:as_system).and_raise(StandardError, 'falhou')

    opportunity = deal

    expect(opportunity).to be_persisted
    expect(opportunity.activities.where(kind: %i[note automation])).to be_empty
    expect(ChatwootExceptionTracker).to have_received(:new)
  end
end
