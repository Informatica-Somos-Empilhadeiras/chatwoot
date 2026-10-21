require 'rails_helper'

RSpec.describe 'Outsider CRM switch per account and per agent', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :agent, name: 'Marta Gestora') }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Bia Vendedora') }
  let(:unit) { crm_unit(account, name: 'Locação') }
  let!(:pipeline) { crm_pipeline(account, unit) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }

  before do
    unit.members.create!(account: account, user: manager, role: :manager)
    unit.members.create!(account: account, user: seller, role: :seller)
  end

  def turn_agent(user, enabled, as: admin)
    patch "#{base_url}/agent_accesses/#{user.id}", params: { enabled: enabled }, headers: as.create_new_auth_token, as: :json
  end

  it 'closes the whole CRM API when the account is off, administrators included' do
    crm_enable(account, enabled: false)

    get "#{base_url}/opportunities", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    get "#{base_url}/access", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('enabled' => false, 'administrator' => true, 'reason' => 'account', 'units' => [])
  end

  it 'lets the account administrator turn the CRM off and on for an agent' do
    turn_agent(seller, false)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => seller.id, 'enabled' => false, 'units' => ['Locação'])

    get "#{base_url}/opportunities", headers: seller.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq('error' => 'crm_access_denied', 'reason' => 'agent')
    get "#{base_url}/access", headers: seller.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('enabled' => false, 'reason' => 'agent')
    get "#{base_url}/access", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['disabled_user_ids']).to eq([seller.id])

    turn_agent(seller, true)
    get "#{base_url}/opportunities", headers: seller.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'lists everyone in the account with their units and open deals for the administrator only' do
    crm_opportunity(account, unit, pipeline: pipeline, owner: seller)
    crm_opportunity(account, unit, pipeline: pipeline, owner: seller, status: :won)

    get "#{base_url}/agent_accesses", headers: admin.create_new_auth_token, as: :json
    people = response.parsed_body['payload'].index_by { |person| person['id'] }
    expect(people[seller.id]).to include('enabled' => true, 'administrator' => false, 'units' => ['Locação'], 'open_deals' => 1)
    expect(people[admin.id]).to include('enabled' => true, 'administrator' => true)

    get "#{base_url}/agent_accesses", headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    turn_agent(seller, false, as: manager)
    expect(response).to have_http_status(:forbidden)
  end

  it 'refuses administrators, people outside the account and requests without the choice' do
    other_admin = create(:user, account: account, role: :administrator)
    stranger = create(:user)

    turn_agent(other_admin, false)
    expect(response).to have_http_status(:unprocessable_entity)
    turn_agent(stranger, false)
    expect(response).to have_http_status(:not_found)
    patch "#{base_url}/agent_accesses/#{seller.id}", params: {}, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not let a manager give a deal to an agent with the CRM off, but keeps the deals they already own' do
    deal = crm_opportunity(account, unit, pipeline: pipeline, owner: seller)
    other = crm_opportunity(account, unit, pipeline: pipeline, owner: manager)
    turn_agent(seller, false)

    patch "#{base_url}/opportunities/#{other.id}", params: { opportunity: { owner_id: seller.id } },
                                                   headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    patch "#{base_url}/opportunities/#{deal.id}", params: { opportunity: { owner_id: seller.id, title: 'Renovação' } },
                                                  headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(deal.reload).to have_attributes(owner_id: seller.id, title: 'Renovação')
  end
end
