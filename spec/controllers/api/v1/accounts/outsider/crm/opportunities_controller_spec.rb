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
end
