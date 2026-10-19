require 'rails_helper'

RSpec.describe 'Outsider CRM opportunities API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let!(:pipeline) { crm_pipeline(account, unit) }
  let!(:contact) { create(:contact, account: account, name: 'Gustavo Teles') }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/opportunities" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
  end

  describe 'POST create' do
    let(:params) { { opportunity: { business_unit_id: unit.id, contact_id: contact.id, title: 'Renovação', value: '68.000,50' } } }

    it 'creates in the first stage, owned by the creator, reusing the Chatwoot contact' do
      expect do
        post url, params: params, headers: seller.create_new_auth_token, as: :json
      end.not_to change(Contact, :count)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('value_cents' => 6_800_050, 'stage_id' => pipeline.first_open_stage.id, 'code' => 'OP-1')
      expect(body['owner']['id']).to eq(seller.id)
      expect(body['contact']['name']).to eq('Gustavo Teles')
    end

    it 'reuses the open journey of the contact' do
      journey = Outsider::Crm::Journey.create!(account: account, contact: contact)
      post url, params: params, headers: seller.create_new_auth_token, as: :json

      expect(response.parsed_body['journey_id']).to eq(journey.id)
    end

    it 'refuses a second open opportunity for the contact in the unit' do
      post url, params: params, headers: seller.create_new_auth_token, as: :json
      post url, params: params, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses a contact from another account' do
      post url, params: { opportunity: params[:opportunity].merge(contact_id: create(:contact).id) },
                headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not let a seller create for a colleague' do
      post url, params: { opportunity: params[:opportunity].merge(owner_id: colleague.id) }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'does not let an agent create in a unit they are not part of' do
      other_unit = crm_unit(account, name: 'Seminovos')
      crm_pipeline(account, other_unit)
      post url, params: { opportunity: params[:opportunity].merge(business_unit_id: other_unit.id) }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH update' do
    let!(:opportunity) { crm_opportunity(account, unit, contact: contact, owner: seller, pipeline: pipeline) }

    it 'moves the stage and marks as won' do
      patch "#{url}/#{opportunity.id}", params: { opportunity: { stage_id: pipeline.stages.second.id, value: 1500 } },
                                        headers: seller.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('value_cents' => 150_000, 'stage_id' => pipeline.stages.second.id)

      patch "#{url}/#{opportunity.id}", params: { opportunity: { status: 'won' } }, headers: seller.create_new_auth_token, as: :json
      expect(response.parsed_body['status']).to eq('won')
    end

    it "does not let a seller edit a colleague's opportunity" do
      patch "#{url}/#{opportunity.id}", params: { opportunity: { title: 'X' } }, headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a stage from another pipeline' do
      other_stage = crm_pipeline(account, unit, name: 'Outro').first_open_stage
      patch "#{url}/#{opportunity.id}", params: { opportunity: { stage_id: other_stage.id } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an invalid status' do
      patch "#{url}/#{opportunity.id}", params: { opportunity: { status: 'whatever' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET index' do
    it 'lists only the units the agent belongs to and searches by contact name' do
      own = crm_opportunity(account, unit, contact: contact, owner: seller, pipeline: pipeline)
      crm_opportunity(account, crm_unit(account, name: 'Seminovos'))

      get url, params: { q: 'gustavo' }, headers: seller.create_new_auth_token
      expect(response.parsed_body['payload'].pluck('id')).to eq([own.id])

      get url, headers: admin.create_new_auth_token
      expect(response.parsed_body['meta']['count']).to eq(2)
    end
  end

  describe 'Kanban' do
    let(:first_stage) { pipeline.first_open_stage }
    let(:second_stage) { pipeline.stages.second }
    let!(:cards) do
      Array.new(3) do |index|
        crm_opportunity(account, unit, owner: seller, pipeline: pipeline, position: index, value_cents: (index + 1) * 10_000)
      end
    end

    it 'returns the open stages with count, total and ordered cards' do
      get "#{url}/board", params: { pipeline_id: pipeline.id }, headers: seller.create_new_auth_token

      stages = response.parsed_body['stages']
      expect(stages.pluck('name')).to eq(%w[Qualificação Proposta])
      expect(stages.first).to include('count' => 3, 'total_cents' => 60_000)
      expect(stages.first['opportunities'].pluck('id')).to eq(cards.map(&:id))
    end

    it 'hides the pipeline of a unit the agent is not part of' do
      other_pipeline = crm_pipeline(account, crm_unit(account, name: 'Seminovos'))
      get "#{url}/board", params: { pipeline_id: other_pipeline.id }, headers: seller.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'reorders inside the stage' do
      patch "#{url}/#{cards.last.id}/move", params: { stage_id: first_stage.id, index: 0 }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(first_stage.opportunities.order(:position).pluck(:id)).to eq([cards[2].id, cards[0].id, cards[1].id])
    end

    it 'moves to another stage at the given position and records it on the timeline' do
      other = crm_opportunity(account, unit, owner: seller, pipeline: pipeline, stage: second_stage)
      patch "#{url}/#{cards.first.id}/move", params: { stage_id: second_stage.id, index: 0 }, headers: seller.create_new_auth_token, as: :json

      expect(response.parsed_body['stage_id']).to eq(second_stage.id)
      expect(second_stage.opportunities.order(:position).pluck(:id)).to eq([cards.first.id, other.id])
      expect(cards.first.activities.where(kind: :stage_changed)).to exist
    end

    it 'closes the deal when dropped on the won stage' do
      won_stage = pipeline.stages.find_by(kind: :won)
      patch "#{url}/#{cards.first.id}/move", params: { stage_id: won_stage.id, index: 0 }, headers: seller.create_new_auth_token, as: :json

      expect(response.parsed_body['status']).to eq('won')
    end

    it 'refuses a stage from another pipeline' do
      other_stage = crm_pipeline(account, unit, name: 'Outro').first_open_stage
      patch "#{url}/#{cards.first.id}/move", params: { stage_id: other_stage.id, index: 0 }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not let a seller move a colleague's card" do
      patch "#{url}/#{cards.first.id}/move", params: { stage_id: second_stage.id, index: 0 }, headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'summarizes open value, weighted forecast and conversion' do
      cards.first.update!(status: :won)
      get "#{url}/summary", params: { pipeline_id: pipeline.id, period: 'month' }, headers: seller.create_new_auth_token

      expect(response.parsed_body).to include(
        'open_count' => 2, 'open_value_cents' => 50_000, 'weighted_value_cents' => 15_000,
        'won_count' => 1, 'won_value_cents' => 10_000, 'lost_count' => 0, 'conversion_rate' => 100.0
      )
    end

    it 'exports the visible deals as CSV' do
      get "#{url}/export", headers: seller.create_new_auth_token

      expect(response.headers['Content-Type']).to include('text/csv')
      lines = response.body.delete_prefix("\uFEFF").lines
      expect(lines.first).to start_with('codigo;negocio;contato')
      expect(lines.size).to eq(4)
      expect(lines.last).to include('aberto')
    end
  end
end
