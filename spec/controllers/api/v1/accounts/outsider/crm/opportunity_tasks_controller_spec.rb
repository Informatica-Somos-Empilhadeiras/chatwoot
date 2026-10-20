require 'rails_helper'

RSpec.describe 'Outsider CRM opportunity tasks API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:opportunity) { crm_opportunity(account, unit, owner: seller) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}/tasks" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
    unit.members.create!(account: account, user: manager, role: :manager)
  end

  def create_task(**attrs)
    opportunity.tasks.create!({ account: account, title: 'Ligar para o cliente', assignee: seller }.merge(attrs))
  end

  describe 'POST create' do
    it 'creates a task for the owner and logs it on the timeline' do
      post url, params: { task: { title: 'Enviar proposta', kind: 'proposal', due_at: 1.day.from_now.iso8601 } },
                headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('title' => 'Enviar proposta', 'kind' => 'proposal', 'can_complete' => true, 'overdue' => false)
      expect(body['assignee']['id']).to eq(seller.id)
      expect(opportunity.activities.task_created.last.metadata).to include('title' => 'Enviar proposta')
    end

    it 'does not let a seller assign the task to someone else' do
      post url, params: { task: { title: 'Visita', assignee_id: colleague.id } }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'lets a manager assign to a unit member, but not to someone outside the unit' do
      post url, params: { task: { title: 'Visita', assignee_id: colleague.id } }, headers: manager.create_new_auth_token, as: :json
      expect(response.parsed_body['assignee']['id']).to eq(colleague.id)

      outsider = create(:user, account: account, role: :agent)
      post url, params: { task: { title: 'Visita', assignee_id: outsider.id } }, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a colleague who only views the opportunity' do
      post url, params: { task: { title: 'Visita' } }, headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET index' do
    it 'lists pending tasks first, by due date, flagging the overdue ones' do
      done = create_task(title: 'Feita', completed_at: 1.hour.ago)
      later = create_task(title: 'Depois', due_at: 2.days.from_now)
      late = create_task(title: 'Atrasada', due_at: 1.hour.ago)

      get url, headers: colleague.create_new_auth_token

      body = response.parsed_body
      expect(body.pluck('id')).to eq([late.id, later.id, done.id])
      expect(body.first).to include('overdue' => true, 'can_edit' => false, 'can_complete' => false)
    end
  end

  describe 'PATCH update' do
    it 'completes and reopens a task, logging the completion' do
      task = create_task

      patch "#{url}/#{task.id}", params: { task: { completed: true } }, headers: seller.create_new_auth_token, as: :json
      expect(response.parsed_body['completed_by']['id']).to eq(seller.id)
      expect(opportunity.activities.task_completed.count).to eq(1)

      patch "#{url}/#{task.id}", params: { task: { completed: false } }, headers: seller.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('completed_at' => nil, 'completed_by' => nil)
    end

    it 'lets the assignee postpone a task on a deal they cannot edit, but nothing else' do
      task = create_task(assignee: colleague, due_at: 1.hour.ago)
      new_due = 2.days.from_now.change(usec: 0)

      patch "#{url}/#{task.id}", params: { task: { due_at: new_due.iso8601, title: 'Outro título' } },
                                 headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(task.reload.due_at).to eq(new_due)
      expect(task.title).to eq('Ligar para o cliente')
    end

    it 'refuses someone who neither edits the deal nor owns the task' do
      task = create_task

      patch "#{url}/#{task.id}", params: { task: { completed: true } }, headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE destroy' do
    it 'removes the task for whoever edits the deal' do
      task = create_task

      delete "#{url}/#{task.id}", headers: seller.create_new_auth_token

      expect(response).to have_http_status(:no_content)
      expect(Outsider::Crm::Task.exists?(task.id)).to be(false)
    end
  end

  it 'adds the pending and overdue counts to the opportunity' do
    create_task(due_at: 1.hour.ago)
    create_task(due_at: 1.day.from_now)
    create_task(completed_at: Time.current)

    get "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}", headers: seller.create_new_auth_token

    expect(response.parsed_body['tasks']).to include('pending' => 2, 'overdue' => 1)
  end

  it 'hides the tasks of an opportunity in another unit' do
    other = crm_opportunity(account, crm_unit(account, name: 'Seminovos'))

    get "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{other.id}/tasks", headers: seller.create_new_auth_token

    expect(response).to have_http_status(:not_found)
  end
end
