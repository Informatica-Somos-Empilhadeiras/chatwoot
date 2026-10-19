require 'rails_helper'

RSpec.describe 'Outsider CRM business units API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }

  describe 'GET access' do
    it 'returns unauthorized without a session' do
      get "#{base_url}/access"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'tells an agent outside every unit that the CRM is off' do
      get "#{base_url}/access", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('enabled' => false, 'administrator' => false)
      expect(response.parsed_body['settings']).to include('max_forward_attempts' => 3)
    end
  end

  describe 'business units' do
    it 'lets an administrator create a unit and add a member' do
      post "#{base_url}/business_units", params: { business_unit: { name: 'Seminovos' } },
                                         headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      unit_id = response.parsed_body['id']

      post "#{base_url}/business_units/#{unit_id}/members", params: { user_id: agent.id, role: 'manager' },
                                                            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      get "#{base_url}/business_units", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body.pluck('name')).to eq(['Seminovos'])
    end

    it 'refuses a member from another account' do
      unit = Outsider::Crm::BusinessUnit.create!(account: account, name: 'Locação')

      post "#{base_url}/business_units/#{unit.id}/members", params: { user_id: create(:user).id },
                                                            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'blocks agents from changing units' do
      Outsider::Crm::BusinessUnit.create!(account: account, name: 'Locação').members.create!(account: account, user: agent)

      post "#{base_url}/business_units", params: { business_unit: { name: 'X' } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'blocks agents outside every unit' do
      get "#{base_url}/business_units", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'does not show units of another account' do
      other_unit = Outsider::Crm::BusinessUnit.create!(account: create(:account), name: 'Alheia')

      get "#{base_url}/business_units/#{other_unit.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'settings' do
    it 'validates the forwarding limit' do
      patch "#{base_url}/settings", params: { settings: { max_forward_attempts: 50 } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      patch "#{base_url}/settings", params: { settings: { max_forward_attempts: 2 } }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('max_forward_attempts' => 2)
    end
  end
end
