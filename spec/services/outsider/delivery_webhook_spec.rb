require 'rails_helper'

RSpec.describe Outsider::DeliveryWebhook do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Bom dia') }
  let(:payload) { Outsider::EvolutionApi.message_created_payload(message) }

  around { |example| with_modified_env(OUTSIDER_DELIVERY_CHECK: 'true', EVOLUTION_API_KEY: 'chave') { example.run } }

  before { Redis::Alfred.scan_each(match: 'outsider_delivery_check:*') { |key| Redis::Alfred.delete(key) } }

  it 'records when the webhook left and asks for the check right after it' do
    allow(SafeFetch).to receive(:fetch)

    expect { Webhooks::Trigger.execute(channel.webhook_url, payload, :api_inbox_webhook) }
      .to have_enqueued_job(Outsider::DeliveryCheckJob).with(inbox.id).on_queue('medium')
    expect(Redis::Alfred.get("outsider_delivery_check:webhook:#{message.id}").to_i).to be_within(5).of(Time.current.to_i)
  end

  it 'leaves the message to the check when Evolution takes longer than the webhook waits' do
    allow(SafeFetch).to receive(:fetch) do
      raise Net::ReadTimeout
    rescue Net::ReadTimeout => e
      raise SafeFetch::FetchError, e.message
    end

    Webhooks::Trigger.execute(channel.webhook_url, payload, :api_inbox_webhook)

    expect(message.reload.status).to eq('sent')
  end

  it 'still fails the message at once when Evolution is down' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('502 Bad Gateway'))

    Webhooks::Trigger.execute(channel.webhook_url, payload, :api_inbox_webhook)

    expect(message.reload).to have_attributes(status: 'failed', external_error: '502 Bad Gateway')
  end

  it 'leaves the webhooks of messages that are not being checked alone' do
    note = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true)
    allow(SafeFetch).to receive(:fetch)

    expect { Webhooks::Trigger.execute(channel.webhook_url, Outsider::EvolutionApi.message_created_payload(note), :api_inbox_webhook) }
      .not_to have_enqueued_job(Outsider::DeliveryCheckJob)
  end
end
