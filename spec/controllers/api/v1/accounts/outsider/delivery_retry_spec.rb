require 'rails_helper'

RSpec.describe 'Outsider delivery retry', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Bom dia', status: :failed,
                     content_attributes: { external_error: 'erro' })
  end

  around { |example| with_modified_env(OUTSIDER_DELIVERY_CHECK: 'true', EVOLUTION_API_KEY: 'chave') { example.run } }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'sends the failed message to Evolution again and puts it back in the check' do
    path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/retry"

    expect { post path, headers: agent.create_new_auth_token, as: :json }.to have_enqueued_job(WebhookJob).with(
      channel.webhook_url, hash_including(event: 'message_created', id: message.id), :api_inbox_webhook, anything
    )
    expect(response).to have_http_status(:success)
    expect(message.reload).to have_attributes(status: 'sent', external_error: nil)
    expect(message.content_attributes['outsider_delivery']).to eq('checking')
  end

  it 'answers as before when the message does not exist' do
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/0/retry", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
