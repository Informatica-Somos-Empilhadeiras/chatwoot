require 'rails_helper'

RSpec.describe Outsider::Crm::TimedRules do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:proposal) { pipeline.stages.find_by(name: 'Proposta') }
  let(:rules) { Outsider::Crm::AutomationRules.new(account) }

  def deal(**attrs)
    crm_opportunity(account, unit, pipeline: pipeline, owner: seller, **attrs)
  end

  def rule(trigger, wait_hours, **attrs)
    rules.create({ name: trigger, trigger: trigger, wait_hours: wait_hours,
                   actions: [{ type: 'create_task', title: "Tarefa #{trigger}", due_in_hours: 0 }] }.merge(attrs))
  end

  it 'runs a stalled rule once per stage visit, only for deals inside the conditions' do
    rule('stalled', 48, conditions: { stage_id: proposal.id, pipeline_id: pipeline.id })
    stalled = travel_to(3.days.ago) { deal(stage: proposal) }
    travel_to(3.days.ago) { deal }
    travel_to(1.day.ago) { deal(stage: proposal) }

    expect(described_class.new(account).perform).to eq(1)
    expect(described_class.new(account).perform).to eq(0)
    expect(stalled.activities.automation.last.metadata)
      .to include('rule' => 'custom', 'rule_id' => 1, 'tasks' => 1, 'key' => stalled.stage_changed_at.utc.iso8601)

    stalled.update!(stage: pipeline.first_open_stage)
    stalled.update!(stage: proposal)
    travel_to(3.days.from_now) { expect(described_class.new(account).perform).to eq(2) }
  end

  it 'charges the next task of deals left without one, counting from the last completed task' do
    rule('no_next_task', 24)
    idle = travel_to(2.days.ago) { deal }
    busy = travel_to(2.days.ago) { deal }
    busy.tasks.create!(account: account, title: 'Ligar', due_at: 1.day.from_now)
    travel_to(2.days.ago) { deal.update!(status: :won) }

    expect(described_class.new(account).perform).to eq(1)
    task = idle.tasks.last
    expect(task).to have_attributes(title: 'Tarefa no_next_task', assignee_id: seller.id)
    expect(described_class.new(account).perform).to eq(0)

    task.complete!(seller)
    expect(described_class.new(account).perform).to eq(0)
    travel_to(25.hours.from_now) { expect(described_class.new(account).perform).to eq(1) }
  end

  it 'runs from the hourly job only in accounts that have rules, skipping inactive ones' do
    rule('stalled', 1, active: false)
    rule('no_next_task', 1)
    other = create(:account)
    idle = travel_to(2.hours.ago) { deal }
    travel_to(2.hours.ago) { crm_opportunity(other, crm_unit(other)) }

    Outsider::Crm::StalledOpportunitiesJob.perform_now

    expect(idle.tasks.pluck(:title)).to eq(['Tarefa no_next_task'])
    expect(Outsider::Crm::Task.where(account_id: other.id)).to be_empty
  end
end
