require 'rails_helper'

RSpec.describe 'Outsider CRM lost deal handed to the next unit', type: :request do
  # o perdido que o repasse em sequência mandou adiante continua perdido, mas não muda mais
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:matriz) { crm_unit(account, name: 'Matriz') }
  let(:df) { crm_unit(account, name: 'Filial DF') }
  let(:pipeline) { crm_pipeline(account, matriz) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm/opportunities" }
  let(:origin) { crm_opportunity(account, matriz, pipeline: pipeline, owner: admin) }
  let!(:task) do
    origin.tasks.create!(account: account, kind: :call, title: 'Ligar', due_at: 1.day.from_now, assignee: admin, created_by: admin)
  end

  before do
    crm_pipeline(account, df)
    Outsider::Crm::Settings.new(account).update(chain_enabled: true, chain_unit_ids: [matriz.id, df.id])
    patch "#{base_url}/#{origin.id}", params: { opportunity: { status: 'lost' } }, headers: admin.create_new_auth_token, as: :json
  end

  it 'shows where it went and refuses changes, moves and notes, even from the admin' do
    expect(response.parsed_body).to include('status' => 'lost', 'can_edit' => false,
                                            'forwarded_to' => include('business_unit_name' => 'Filial DF'))

    patch "#{base_url}/#{origin.id}", params: { opportunity: { status: 'open' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    patch "#{base_url}/#{origin.id}/move", params: { stage_id: pipeline.first_open_stage.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{base_url}/#{origin.id}/activities", params: { activity: { body: 'Oi' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(origin.reload).to have_attributes(status: 'lost', handed_off?: true)
  end

  it 'checks again inside the lock, so a stale screen cannot reopen it' do
    allow(Outsider::Crm::Access).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |access| allow(access).to receive(:edit_opportunity?).and_return(true, false) }
    end

    patch "#{base_url}/#{origin.id}", params: { opportunity: { status: 'open' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(origin.reload.status).to eq('lost')
  end

  it 'keeps the tasks closed by the handoff closed' do
    expect(task.reload.completed_at).to be_present

    patch "#{base_url}/#{origin.id}/tasks/#{task.id}", params: { task: { completed: false } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(task.reload.completed_at).to be_present
  end

  it 'counts as lost in its unit and also as sent to another unit, outside the forwarding reasons' do
    get "#{base_url}/summary", params: { business_unit_id: matriz.id, owner_id: admin.id }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('lost_count' => 1)

    get "/api/v1/accounts/#{account.id}/outsider/crm/reports", params: { period: 'month' }, headers: admin.create_new_auth_token
    report = response.parsed_body
    expect(report['summary']).to include('lost_count' => 1, 'forwarded_count' => 1, 'received_count' => 1)
    expect(report['units'].find { |row| row['name'] == 'Matriz' }).to include('lost_count' => 1, 'forwarded_count' => 1)
    expect(report['forward_reasons']).to be_empty
  end
end
