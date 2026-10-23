require 'rails_helper'

describe Outsider::InstantBroadcast do
  let(:listener) { ActionCableListener.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Current.user = nil
  end

  it 'sends a new conversation right away and keeps the other events in the queue' do
    allow(ActionCableBroadcastJob).to receive(:perform_now)
    allow(ActionCableBroadcastJob).to receive(:perform_later)

    listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conversation))
    listener.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))

    expect(ActionCableBroadcastJob).to have_received(:perform_now)
      .with(array_including(agent.pubsub_token), 'conversation.created', conversation.push_event_data.merge(account_id: account.id))
    expect(ActionCableBroadcastJob).to have_received(:perform_later).with(array_including(agent.pubsub_token), 'conversation.updated', anything)
  end
end
