require 'rails_helper'

RSpec.describe 'Outsider CRM pipelines API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/pipelines" }
  let(:stages) { [{ name: 'Lead', position: 1 }, { name: 'Ganho', position: 2, kind: 'won', probability: 100 }] }

  before do
    unit.members.create!(account: account, user: manager, role: :manager)
    unit.members.create!(account: account, user: seller, role: :seller)
  end

  it 'lets a unit manager create a pipeline with stages' do
    post url, params: { pipeline: { business_unit_id: unit.id, name: 'Funil 2026', stages_attributes: stages } },
              headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['stages'].pluck('name')).to eq(%w[Lead Ganho])
  end

  it 'refuses a pipeline without an open stage' do
    post url, params: { pipeline: { business_unit_id: unit.id, name: 'X', stages_attributes: [stages.last] } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not let a seller change pipelines' do
    post url, params: { pipeline: { business_unit_id: unit.id, name: 'X', stages_attributes: stages } },
              headers: seller.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps a stage that still has opportunities' do
    pipeline = crm_pipeline(account, unit)
    crm_opportunity(account, unit, pipeline: pipeline)
    stage = pipeline.first_open_stage

    patch "#{url}/#{pipeline.id}", params: { pipeline: { stages_attributes: [{ id: stage.id, _destroy: true }] } },
                                   headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(stage.reload).to be_present
  end

  it 'renames and reorders stages' do
    pipeline = crm_pipeline(account, unit)
    first, second = pipeline.stages.first(2)

    stages = [{ id: first.id, position: 2 }, { id: second.id, position: 1, name: 'Diagnóstico' }]
    patch "#{url}/#{pipeline.id}", params: { pipeline: { stages_attributes: stages } }, headers: manager.create_new_auth_token, as: :json

    expect(response.parsed_body['stages'].first(2).pluck('name')).to eq(%w[Diagnóstico Qualificação])
  end
end
