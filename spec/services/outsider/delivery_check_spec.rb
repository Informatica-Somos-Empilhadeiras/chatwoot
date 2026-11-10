require 'rails_helper'

RSpec.describe Outsider::DeliveryCheck do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let(:api) { instance_double(Outsider::EvolutionApi, instance: 'CENTRAL') }
  let(:records) { [] }
  let(:push) { instance_double(Outsider::Push::UndeliveredMessage, perform: 1) }

  around { |example| with_modified_env(OUTSIDER_DELIVERY_CHECK: 'true', EVOLUTION_API_KEY: 'chave') { example.run } }

  before do
    Redis::Alfred.scan_each(match: 'outsider_delivery_check:*') { |key| Redis::Alfred.delete(key) }
    allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api)
    allow(api).to receive(:find_all_messages) { records }
    allow(Outsider::Push::UndeliveredMessage).to receive(:new).and_return(push)
  end

  def sent(content, **attrs)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: content }.merge(attrs))
  end

  def record(id, text: nil, type: 'conversation', at: Time.current, statuses: [])
    { 'key' => { 'id' => id, 'fromMe' => true, 'remoteJid' => customer.identifier }, 'messageType' => type, 'messageTimestamp' => at.to_i,
      'message' => text ? { 'conversation' => text } : { type => {} }, 'MessageUpdate' => statuses.map { |status| { 'status' => status } } }
  end

  def proven
    Redis::Alfred.setex("outsider_delivery_check:proven:#{inbox.id}", 1, 1.day.to_i)
  end

  # o webhook da mensagem foi para a Evolution há 3 minutos: o prazo do texto (2 min) já passou
  def check_after_deadline(*messages)
    messages.each { |message| described_class.webhook_started(message.id) }
    travel(3.minutes) { described_class.new(inbox).perform }
  end

  describe 'a new message' do
    it 'starts being checked when it leaves through Evolution' do
      expect(sent('Bom dia').content_attributes['outsider_delivery']).to eq('checking')
    end

    it 'is left alone when it is a note, a copy from WhatsApp, a bot command or from another kind of inbox' do
      robot = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account, phone_number: '+123456'))
      other = create(:conversation, account: account)
      messages = [sent('nota', private: true), sent('do celular', source_id: 'WAID:ABC'), sent('/status', conversation: robot),
                  sent('oi', conversation: other, inbox: other.inbox), sent('recebida', message_type: :incoming)]

      expect(messages.map { |message| message.content_attributes['outsider_delivery'] }).to all(be_nil)
    end

    it 'is left alone when the check is off' do
      with_modified_env(OUTSIDER_DELIVERY_CHECK: 'false') do
        expect(sent('Bom dia').content_attributes['outsider_delivery']).to be_nil
      end
    end
  end

  describe 'confirming with Evolution' do
    it 'links the message to the one sent on WhatsApp, signature and formatting included' do
      message = sent('Segue a **proposta**')
      records << record('WA1', text: "*Maria:*\nSegue a *proposta*", statuses: %w[SERVER_ACK])

      described_class.new(inbox).perform

      expect(message.reload).to have_attributes(source_id: 'WAID:WA1', status: 'sent')
      expect(message.content_attributes['outsider_delivery']).to eq('confirmed')
    end

    it 'shows delivered and read as WhatsApp reports them' do
      delivered = sent('Chegou?')
      read = sent('Leu?')
      records.push(record('WA1', text: 'Chegou?', statuses: %w[SERVER_ACK DELIVERY_ACK]),
                   record('WA2', text: 'Leu?', statuses: %w[DELIVERY_ACK READ]))

      described_class.new(inbox).perform

      expect([delivered.reload.status, read.reload.status]).to eq(%w[delivered read])
      expect(Outsider::Push::UndeliveredMessage).not_to have_received(:new)
    end

    it 'fails the message WhatsApp refused' do
      message = sent('Olá')
      records << record('WA1', text: 'Olá', statuses: %w[ERROR])

      described_class.new(inbox).perform

      expect(message.reload).to have_attributes(status: 'failed', source_id: 'WAID:WA1')
      expect(message.external_error).to eq(I18n.t('outsider_delivery.refused'))
    end

    it 'ignores what was sent to another chat, before the message or already belongs to another message' do
      sent('do celular', source_id: 'WAID:PHONE')
      message = sent('ok')
      records.push(record('OTHER', text: 'ok').deep_merge('key' => { 'remoteJid' => '5562988887777@s.whatsapp.net' }),
                   record('OLD', text: 'ok', at: 5.minutes.ago), record('PHONE', text: 'ok'))

      described_class.new(inbox).perform

      expect(message.reload.source_id).to be_nil
      expect(message.content_attributes['outsider_delivery']).to eq('checking')
    end

    it 'finds the chat by the number without the ninth digit and by the address WhatsApp sends beside the new one' do
      first = sent('Bom dia')
      second = sent('Boa tarde')
      new_address = { 'remoteJid' => '98765432101234@lid', 'remoteJidAlt' => customer.identifier }
      records.push(record('WA1', text: 'Bom dia').deep_merge('key' => { 'remoteJid' => '556299990001@s.whatsapp.net' }),
                   record('WA2', text: 'Boa tarde').deep_merge('key' => new_address))

      described_class.new(inbox).perform

      expect([first.reload.source_id, second.reload.source_id]).to eq(%w[WAID:WA1 WAID:WA2])
    end

    it 'confirms each of two equal texts with its own WhatsApp message' do
      first = sent('ok')
      second = sent('ok')
      records.push(record('WA2', text: 'ok', at: 2.seconds.from_now), record('WA1', text: 'ok'))

      described_class.new(inbox).perform

      expect([first.reload.source_id, second.reload.source_id]).to contain_exactly('WAID:WA1', 'WAID:WA2')
    end

    it 'gives the WhatsApp message to the repeated text, not to the one that failed before it' do
      failed = sent('Segue a proposta', created_at: 5.minutes.ago)
      repeated = sent('Segue a proposta')
      records << record('WA1', text: 'Segue a proposta', at: 2.seconds.from_now)

      described_class.new(inbox).perform

      expect([failed.reload.source_id, repeated.reload.source_id]).to eq([nil, 'WAID:WA1'])
    end

    it 'does not confirm two conversations of the same contact with one WhatsApp message' do
      other = create(:conversation, account: account, inbox: inbox, contact: customer)
      messages = [sent('ok'), sent('ok', conversation: other)]
      records << record('WA1', text: 'ok', at: 2.seconds.from_now)

      described_class.new(inbox).perform

      expect(messages.filter_map { |message| message.reload.source_id }).to eq(%w[WAID:WA1])
    end

    it 'wants one WhatsApp message for each attachment' do
      message = build(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: nil)
      2.times do
        message.attachments.new(account_id: account.id, file_type: :image,
                                file: { io: Rails.root.join('spec/assets/avatar.png').open, filename: 'foto.png', content_type: 'image/png' })
      end
      message.save!
      records << record('WA1', type: 'imageMessage')

      described_class.new(inbox).perform
      expect(message.reload.content_attributes['outsider_delivery']).to eq('checking')

      records << record('WA2', type: 'imageMessage', statuses: %w[DELIVERY_ACK])
      described_class.new(inbox).perform

      expect(message.reload).to have_attributes(source_id: 'WAID:WA1', status: 'sent')
      expect(message.content_attributes['outsider_wa_ids']).to eq(%w[WA1 WA2])
    end
  end

  describe 'a message Evolution never sent' do
    it 'waits for the deadline and then fails, telling the agent to check before resending' do
      message = sent('Bom dia')
      proven
      described_class.webhook_started(message.id)

      described_class.new(inbox).perform
      expect(message.reload.status).to eq('sent')

      travel(3.minutes) { described_class.new(inbox).perform }

      expect(message.reload).to have_attributes(status: 'failed', external_error: I18n.t('outsider_delivery.unconfirmed'))
      expect(message.content_attributes['outsider_delivery']).to eq('unconfirmed')
      expect(Outsider::Push::UndeliveredMessage).to have_received(:new).with(message).once
    end

    it 'counts the deadline from the webhook, not from the creation' do
      message = sent('Bom dia', created_at: 10.minutes.ago)
      proven
      described_class.webhook_started(message.id)

      described_class.new(inbox).perform

      expect(message.reload.status).to eq('sent')
    end

    it 'goes back to the plain sent mark while the check has not confirmed anything in the inbox' do
      message = sent('Bom dia')

      check_after_deadline(message)

      expect(message.reload.status).to eq('sent')
      expect(message.content_attributes).not_to have_key('outsider_delivery')
    end

    it 'trusts the check once another message of the inbox is confirmed' do
      lost = sent('Perdida')
      found = sent('Achada')
      records << record('WA1', text: 'Achada', at: 3.minutes.from_now)

      check_after_deadline(lost, found)

      expect([lost.reload.status, found.reload.status]).to eq(%w[failed sent])
    end

    it 'takes the message sent right after it when the text does not match' do
      message = sent('Texto que a Evolution mudou')
      proven
      records << record('WA1', text: 'outro texto', at: 20.seconds.from_now)

      check_after_deadline(message)

      expect(message.reload).to have_attributes(source_id: 'WAID:WA1', status: 'sent')
    end

    it 'clears the failure when the message shows up later' do
      message = sent('Demorou')
      proven
      check_after_deadline(message)
      records << record('WA1', text: 'Demorou', at: 4.minutes.from_now, statuses: %w[DELIVERY_ACK])

      travel(5.minutes) { described_class.new(inbox).perform }

      expect(message.reload).to have_attributes(status: 'delivered', source_id: 'WAID:WA1', external_error: nil)
    end
  end

  describe 'following a sent message' do
    it 'turns it into delivered, read or failed' do
      delivered = sent('a', source_id: 'WAID:WA1')
      failed = sent('b', source_id: 'WAID:WA2')
      waiting = sent('c', source_id: 'WAID:WA3')
      records.push(record('WA1', text: 'a', statuses: %w[SERVER_ACK DELIVERY_ACK]), record('WA2', text: 'b', statuses: %w[ERROR]),
                   record('WA3', text: 'c', statuses: %w[SERVER_ACK]))

      described_class.new(inbox).perform

      expect([delivered, failed, waiting].map { |message| message.reload.status }).to eq(%w[delivered failed sent])
    end

    it 'leaves the following to the check of every minute' do
      sent('a', source_id: 'WAID:WA1')

      described_class.new(inbox).perform(follow: false)

      expect(api).not_to have_received(:find_all_messages)
    end

    it 'does not follow group messages, which WhatsApp never reports as delivered' do
      group = create(:contact, account: account, identifier: '120363000000000000@g.us')
      sent('aviso', source_id: 'WAID:WA1', conversation: create(:conversation, account: account, inbox: inbox, contact: group))

      described_class.new(inbox).perform

      expect(api).not_to have_received(:find_all_messages)
    end

    it 'asks Evolution nothing when there is nothing to check' do
      sent('antiga', source_id: 'WAID:WA1', created_at: 2.hours.ago)
      sent('entregue', source_id: 'WAID:WA2', status: :delivered)

      described_class.new(inbox).perform

      expect(api).not_to have_received(:find_all_messages)
    end
  end

  it 'changes nothing when Evolution does not answer' do
    message = sent('Bom dia')
    proven
    allow(api).to receive(:find_all_messages).and_raise(Outsider::EvolutionApi::Error, 'evolution_timeout')

    check_after_deadline(message)

    expect(message.reload.status).to eq('sent')
    expect(message.content_attributes['outsider_delivery']).to eq('checking')
  end

  describe '.resend' do
    it 'sends the message to Evolution again and restarts the check' do
      message = sent('Bom dia', status: :failed, source_id: 'WAID:OLD')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, source_id: 'WAID:REPLY')

      expect { described_class.resend(message) }.to have_enqueued_job(WebhookJob).with(
        channel.webhook_url, hash_including(event: 'message_created', id: message.id), :api_inbox_webhook, anything
      )
      expect(message.reload.source_id).to be_nil
      expect(message.content_attributes).to include('outsider_delivery' => 'checking',
                                                    'outsider_delivery_since' => be_within(5).of(Time.current.to_i))
    end
  end
end
