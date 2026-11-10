require 'rails_helper'

RSpec.describe Outsider::EvolutionWebhooks do
  let(:listener) { WebhookListener.instance }
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Bom dia') }
  let!(:reply) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi', source_id: 'WAID:REPLY')
  end

  def created(message)
    Events::Base.new(:'message.created', Time.zone.now, message: message)
  end

  def updated(message)
    Events::Base.new(:'message.updated', Time.zone.now, message: message)
  end

  it 'sends Evolution the message itself, even when the customer has already answered' do
    expect { listener.message_created(created(message)) }.to(have_enqueued_job(WebhookJob).with do |url, payload, type|
      expect([url, type, payload[:event], payload[:id]]).to eq([channel.webhook_url, :api_inbox_webhook, 'message_created', message.id])
      expect(payload[:conversation][:messages].pluck(:id)).to eq([message.id])
    end)
  end

  it 'does not send Evolution what came from WhatsApp or what only changed' do
    message.update!(status: :delivered)

    expect do
      listener.message_created(created(reply))
      listener.message_updated(updated(message))
    end.not_to have_enqueued_job(WebhookJob)
  end

  it 'still sends Evolution the deleted message' do
    message.update!(content_attributes: { deleted: true })

    expect { listener.message_updated(updated(message)) }
      .to have_enqueued_job(WebhookJob).with(channel.webhook_url, hash_including(event: 'message_updated'), :api_inbox_webhook, anything)
  end

  it 'keeps sending everything to the account webhooks' do
    webhook = create(:webhook, account: account, subscriptions: %w[message_created message_updated])

    expect do
      listener.message_created(created(reply))
      listener.message_updated(updated(message))
    end.to have_enqueued_job(WebhookJob).with(webhook.url, anything, :account_webhook, anything).twice
  end

  it 'leaves the other API inboxes as they were' do
    channel.update!(webhook_url: 'https://example.com/hook')

    expect { listener.message_created(created(reply)) }
      .to have_enqueued_job(WebhookJob).with('https://example.com/hook', hash_including(event: 'message_created'), :api_inbox_webhook, anything)
  end
end
