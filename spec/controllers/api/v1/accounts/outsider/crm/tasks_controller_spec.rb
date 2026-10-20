require 'rails_helper'

RSpec.describe 'Outsider CRM tasks list API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:other_unit) { crm_unit(account, name: 'Seminovos') }
  let(:opportunity) { crm_opportunity(account, unit, owner: seller) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/tasks" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
  end

  def create_task(target = opportunity, **attrs)
    target.tasks.create!({ account: account, title: 'Ligar', assignee: seller }.merge(attrs))
  end

  it 'lists my pending tasks by due date, with the opportunity and counts' do
    late = create_task(due_at: 1.hour.ago)
    later = create_task(due_at: 1.day.from_now)
    create_task(assignee: colleague)
    create_task(completed_at: Time.current)

    get url, headers: seller.create_new_auth_token

    body = response.parsed_body
    expect(body['payload'].pluck('id')).to eq([late.id, later.id])
    expect(body['payload'].first['opportunity']).to include('id' => opportunity.id, 'code' => opportunity.code)
    expect(body['meta']).to eq('pending' => 2, 'overdue' => 1)
  end

  it 'shows everyone else tasks only inside the visible units' do
    create_task(assignee: colleague)
    hidden = create_task(crm_opportunity(account, other_unit), assignee: admin)

    get url, params: { assignee_id: 'all' }, headers: seller.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).not_to include(hidden.id)
    expect(response.parsed_body['payload'].size).to eq(1)

    get url, params: { assignee_id: 'all' }, headers: admin.create_new_auth_token
    expect(response.parsed_body['payload'].size).to eq(2)
  end

  it 'lists the tasks done in the last days and filters by due date' do
    done = create_task(completed_at: 1.day.ago)
    create_task(completed_at: 40.days.ago)
    soon = create_task(due_at: 10.minutes.from_now)
    create_task(due_at: 3.days.from_now)

    get url, params: { status: 'done' }, headers: seller.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([done.id])

    get url, params: { due_before: 1.hour.from_now.iso8601 }, headers: seller.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([soon.id])
  end
end
