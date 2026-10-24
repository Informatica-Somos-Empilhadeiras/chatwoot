require 'rails_helper'

RSpec.describe 'Outsider WhatsApp messages', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/whatsapp_messages/#{message.id}" }
  let(:actions) { instance_double(Outsider::WhatsappMessageActions) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    allow(Outsider::WhatsappMessageActions).to receive(:new).and_return(actions)
  end

  it 'edits the message and sends it back' do
    allow(actions).to receive(:edit).with('Novo texto').and_return(message)

    patch url, params: { content: 'Novo texto' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('message', 'id')).to eq(message.id)
  end

  it 'reacts and reports why it could not' do
    allow(actions).to receive(:react).with('👍')
    post "#{url}/reaction", params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)

    allow(actions).to receive(:react).and_raise(Outsider::WhatsappMessageActions::Invalid, 'not_found')
    post "#{url}/reaction", params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('not_found')
  end

  it 'refuses an agent outside the inbox' do
    post "#{url}/reaction", params: { emoji: '👍' }, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
