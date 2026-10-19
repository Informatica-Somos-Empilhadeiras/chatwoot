require 'rails_helper'

RSpec.describe 'Outsider CRM contacts API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:other_unit) { crm_unit(account, name: 'Seminovos') }
  let!(:pipeline) { crm_pipeline(account, unit) }
  let(:contact) { create(:contact, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/contacts" }

  before { unit.members.create!(account: account, user: seller, role: :seller) }

  describe 'GET show' do
    it 'summarizes the visible opportunities, picking the one linked to the conversation' do
      conversation = create(:conversation, account: account, contact: contact)
      linked = crm_opportunity(account, unit, contact: contact, pipeline: pipeline, conversation: conversation, value_cents: 50_000)
      crm_opportunity(account, unit, contact: contact, pipeline: pipeline, value_cents: 10_000, status: :won,
                                     stage: pipeline.stages.find_by(kind: :won))
      crm_opportunity(account, other_unit, contact: contact, value_cents: 99_000)

      get "#{url}/#{contact.id}", params: { conversation_id: conversation.id }, headers: seller.create_new_auth_token

      body = response.parsed_body
      expect(body).to include('open_count' => 1, 'open_value_cents' => 50_000, 'won_count' => 1, 'primary_id' => linked.id)
      expect(body['opportunities'].size).to eq(2)
      expect(body['creatable_unit_ids']).to eq([])
    end

    it 'offers the units with a pipeline where the contact has no open opportunity' do
      crm_pipeline(account, other_unit)
      crm_unit(account, name: 'Sem pipeline')
      get "#{url}/#{contact.id}", headers: admin.create_new_auth_token

      expect(response.parsed_body['creatable_unit_ids']).to contain_exactly(unit.id, other_unit.id)
    end

    it 'does not offer creation for a WhatsApp group' do
      group = create(:contact, account: account, identifier: '120363012345678901@g.us')
      get "#{url}/#{group.id}", headers: seller.create_new_auth_token

      expect(response.parsed_body).to include('group' => true, 'creatable_unit_ids' => [])
    end

    it 'does not show a contact from another account' do
      get "#{url}/#{create(:contact).id}", headers: seller.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses agents outside the CRM' do
      get "#{url}/#{contact.id}", headers: create(:user, account: account, role: :agent).create_new_auth_token

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET summaries' do
    it 'returns the open value per contact, only for visible units' do
      other = create(:contact, account: account)
      crm_opportunity(account, unit, contact: contact, pipeline: pipeline, value_cents: 68_000)
      crm_opportunity(account, other_unit, contact: other, value_cents: 5_000)

      get "#{url}/summaries", params: { ids: "#{contact.id},#{other.id}" }, headers: seller.create_new_auth_token

      expect(response.parsed_body).to eq(contact.id.to_s => { 'open_count' => 1, 'open_value_cents' => 68_000 })
    end
  end

  describe 'creating from a conversation' do
    it 'links the conversation and refuses a group contact' do
      conversation = create(:conversation, account: account, contact: contact)
      post "/api/v1/accounts/#{account.id}/outsider/crm/opportunities",
           params: { opportunity: { business_unit_id: unit.id, contact_id: contact.id, conversation_id: conversation.id, title: 'Locação' } },
           headers: seller.create_new_auth_token, as: :json
      expect(response.parsed_body['conversation_id']).to eq(conversation.id)

      group = create(:contact, account: account, identifier: '120363012345678901@g.us')
      post "/api/v1/accounts/#{account.id}/outsider/crm/opportunities",
           params: { opportunity: { business_unit_id: unit.id, contact_id: group.id, title: 'Grupo' } },
           headers: seller.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
