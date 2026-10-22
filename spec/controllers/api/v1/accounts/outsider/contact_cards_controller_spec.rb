require 'rails_helper'

RSpec.describe 'Outsider contact cards', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/contact_cards" }
  let(:payload) { { conversation_id: conversation.display_id, contacts: [{ name: 'Daniel', phone: '62991834188' }] } }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'sends for whoever sees the conversation' do
    sender = instance_double(Outsider::ContactCardSender, perform: nil)
    allow(Outsider::ContactCardSender).to receive(:new).and_return(sender)

    post url, params: payload, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(Outsider::ContactCardSender).to have_received(:new).with(
      conversation: conversation, user: agent, contacts: [{ name: 'Daniel', phone: '62991834188' }]
    )
  end

  it 'refuses an agent outside the inbox' do
    post url, params: payload, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers Evolution and validation errors with a code' do
    allow(Outsider::ContactCardSender).to receive(:new).and_raise(Outsider::EvolutionApi::Error, 'evolution_timeout')
    post url, params: payload, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('evolution_timeout')

    allow(Outsider::ContactCardSender).to receive(:new).and_raise(Outsider::ContactCardSender::Invalid, 'invalid_phone')
    post url, params: payload, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('invalid_phone')
  end
end
