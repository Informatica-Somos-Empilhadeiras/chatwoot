require 'rails_helper'

RSpec.describe Outsider::Crm::StalledOpportunities do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:proposal) { pipeline.stages.find_by(name: 'Proposta') }
  let(:settings) { Outsider::Crm::Settings.new(account) }

  def deal(**attrs)
    crm_opportunity(account, unit, pipeline: pipeline, owner: seller, **attrs)
  end

  before { settings.update(automation_stalled_task: true, automation_stalled_days: 3) }

  it 'creates one follow-up task for the owner of each deal stalled past the limit, once per stage visit' do
    stalled = travel_to(4.days.ago) { deal }
    recent = travel_to(1.day.ago) { deal }

    expect(described_class.new(account).perform).to eq(1)

    task = stalled.tasks.last
    expect(task).to have_attributes(kind: 'follow_up', assignee_id: seller.id, created_by_id: nil,
                                    title: I18n.t('outsider_crm.automations.stalled_task_title', stage: 'Qualificação'))
    expect(task.due_at).to be_within(1.minute).of(Time.current)
    expect(stalled.activities.automation.last.metadata).to include('rule' => 'stalled_task', 'stage' => 'Qualificação', 'days' => 4,
                                                                   'task_id' => task.id)
    expect(described_class.new(account).perform).to eq(0)

    stalled.update!(stage: proposal)
    travel_to(4.days.from_now) { described_class.new(account).perform }
    expect([stalled.tasks.count, recent.tasks.count]).to eq([2, 1])
  end

  it 'uses the stage deadline (sla_hours) when the stage has one' do
    proposal.update!(sla_hours: 12)
    travel_to(13.hours.ago) { deal(stage: proposal) }

    expect(described_class.new(account).perform).to eq(1)
  end

  it 'skips closed deals and accounts with the automation off' do
    travel_to(10.days.ago) { deal.update!(status: :won) }
    expect(described_class.new(account).perform).to eq(0)

    settings.update(automation_stalled_task: false)
    travel_to(10.days.ago) { deal }
    expect(described_class.new(account).perform).to eq(0)
  end

  it 'runs every account that turned the automation on from the hourly job' do
    other = create(:account)
    stalled = travel_to(5.days.ago) { deal }
    travel_to(5.days.ago) { crm_opportunity(other, crm_unit(other)) }

    Outsider::Crm::StalledOpportunitiesJob.perform_now

    expect(stalled.tasks.count).to eq(1)
    expect(Outsider::Crm::Task.where(account_id: other.id)).to be_empty
  end

  describe 'check now endpoint', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/automations/stalled" }

    it 'lets the administrator run the check and tells how many tasks were created' do
      travel_to(4.days.ago) { deal }

      post url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('created' => 1)
      expect(Outsider::Crm::Task.last.opportunity.activities.task_created.last.user_id).to be_nil
    end

    it 'is only for administrators' do
      unit.members.create!(account: account, user: seller, role: :manager)

      post url, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
