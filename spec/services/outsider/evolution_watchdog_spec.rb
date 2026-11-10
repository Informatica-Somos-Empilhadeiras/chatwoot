require 'rails_helper'

RSpec.describe Outsider::EvolutionWatchdog do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:api) { instance_double(Outsider::EvolutionApi, instance: 'CENTRAL', restart: {}, connect: {}) }
  let(:notice) { instance_double(Outsider::Push::ConnectionNotice, down: 1, logged_out: 1, back: 1) }

  around { |example| with_modified_env(OUTSIDER_EVOLUTION_WATCHDOG: 'true', EVOLUTION_API_KEY: 'chave') { example.run } }

  before do
    %w[not_open_since acted down_notice logged_out_notice].each { |name| Redis::Alfred.delete("outsider_evolution_watchdog:CENTRAL:#{name}") }
    allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api)
    allow(Outsider::Push::ConnectionNotice).to receive(:new).with([inbox]).and_return(notice)
  end

  def agent_replies(count, at: 10.minutes.ago)
    create_list(:conversation, count, account: account, inbox: inbox).each do |conversation|
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: at)
    end
  end

  context 'when the instance shows as connected' do
    before { allow(api).to receive(:connection_state).and_return('open') }

    it 'restarts it once when nothing arrives while agents wait on 3 conversations' do
      conversations = agent_replies(3)
      create(:message, account: account, inbox: inbox, conversation: conversations.first, message_type: :incoming, created_at: 40.minutes.ago)

      2.times { described_class.new.perform }

      expect(api).to have_received(:restart).once
    end

    it 'leaves it alone when a message arrived or fewer conversations are waiting' do
      conversations = agent_replies(3)
      create(:message, account: account, inbox: inbox, conversation: conversations.first, message_type: :incoming, created_at: 5.minutes.ago)
      described_class.new.perform

      Message.incoming.delete_all
      Message.where(conversation: conversations.last).delete_all
      described_class.new.perform

      expect(api).not_to have_received(:restart)
    end
  end

  it 'restarts an instance stuck connecting for 3 minutes' do
    allow(api).to receive(:connection_state).and_return('connecting')

    described_class.new.perform
    expect(api).not_to have_received(:restart)

    travel 3.minutes do
      described_class.new.perform
    end
    expect(api).to have_received(:restart).once
  end

  it 'opens a closed instance again, but not one logged out on the phone' do
    allow(api).to receive_messages(connection_state: 'close', instance_info: { 'disconnectionReasonCode' => 401 })
    described_class.new.perform
    travel(3.minutes) { described_class.new.perform }
    expect(api).not_to have_received(:connect)

    Redis::Alfred.delete('outsider_evolution_watchdog:CENTRAL:acted')
    allow(api).to receive(:instance_info).and_return({ 'disconnectionReasonCode' => 428 })
    travel(3.minutes) { described_class.new.perform }
    expect(api).to have_received(:connect).once
  end

  it 'tells the people of the inbox once that WhatsApp is down, and that it came back' do
    allow(api).to receive(:connection_state).and_return('connecting')
    described_class.new.perform
    expect(notice).not_to have_received(:down)

    travel(3.minutes) { described_class.new.perform }
    travel(4.minutes) { described_class.new.perform }
    expect(notice).to have_received(:down).with(3).once

    allow(api).to receive(:connection_state).and_return('open')
    travel(7.minutes) { 2.times { described_class.new.perform } }
    expect(notice).to have_received(:back).with(7).once
  end

  it 'tells them once that the phone was logged out, and when Evolution stops answering' do
    allow(api).to receive_messages(connection_state: 'close', instance_info: { 'disconnectionReasonCode' => 401 })
    described_class.new.perform
    travel(3.minutes) { 2.times { described_class.new.perform } }
    expect(notice).to have_received(:logged_out).with(401).once
    expect(notice).not_to have_received(:down)

    allow(api).to receive(:connection_state).and_raise(Outsider::EvolutionApi::Error, 'evolution_unreachable')
    travel(5.minutes) { described_class.new.perform }
    expect(notice).to have_received(:down).with(5).once
  end

  it 'does not announce a comeback nobody was told about' do
    allow(api).to receive(:connection_state).and_return('connecting')
    described_class.new.perform
    allow(api).to receive(:connection_state).and_return('open')
    travel(1.minute) { described_class.new.perform }

    expect(notice).not_to have_received(:back)
  end

  it 'only logs when Evolution does not answer and does nothing when turned off' do
    allow(api).to receive(:connection_state).and_raise(Outsider::EvolutionApi::Error, 'evolution_timeout')
    expect { described_class.new.perform }.not_to raise_error

    with_modified_env(OUTSIDER_EVOLUTION_WATCHDOG: 'false') { described_class.new.perform }
    expect(api).to have_received(:connection_state).once
  end
end
