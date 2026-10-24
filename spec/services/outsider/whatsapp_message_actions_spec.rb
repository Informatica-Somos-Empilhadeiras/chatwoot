require 'rails_helper'

RSpec.describe Outsider::WhatsappMessageActions do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { account.account_users.find_by(user: agent) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let(:api) { instance_double(Outsider::EvolutionApi) }
  let(:key) { { 'id' => 'SENT1', 'remoteJid' => '5562999990001@s.whatsapp.net', 'fromMe' => true } }

  before { allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api) }

  def sent_message(**attrs)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent,
                       content: 'Entrega em **3 dias**' }.merge(attrs))
  end

  describe 'editing' do
    it 'finds the message Chatwoot sent, edits it on WhatsApp keeping the signature and updates the text here' do
      message = sent_message
      sent = { 'key' => key.merge('remoteJid' => '556299990001@s.whatsapp.net'), 'message' => { 'conversation' => "*Daniel:*\nEntrega em *3 dias*" } }
      other = { 'key' => key.merge('id' => 'OTHER', 'remoteJid' => '5511900000000@s.whatsapp.net'),
                'message' => { 'conversation' => 'Entrega em *3 dias*' } }
      allow(api).to receive(:find_messages).and_return({ 'records' => [other, sent] })
      allow(api).to receive(:update_message).and_return({})

      described_class.new(message: message, account_user: account_user).edit('Entrega em **5 dias**')

      expect(api).to have_received(:update_message).with(
        number: '556299990001@s.whatsapp.net', key: key.merge('remoteJid' => '556299990001@s.whatsapp.net'), text: "*Daniel:*\nEntrega em *5 dias*"
      )
      message.reload
      expect(message.content).to eq('Entrega em **5 dias**')
      expect(message.source_id).to eq('WAID:SENT1')
      expect(message.content_attributes['outsider_edited_at']).to be_present
    end

    it 'only edits text sent in the last 15 minutes by the agent' do
      old = sent_message(created_at: 20.minutes.ago)
      theirs = sent_message(sender: create(:user, account: account, role: :agent))
      incoming = sent_message(message_type: :incoming, sender: customer)

      [old, theirs, incoming].each do |message|
        expect { described_class.new(message: message, account_user: account_user).edit('Oi') }
          .to raise_error(described_class::Invalid, 'not_editable')
      end
    end
  end

  describe 'reacting' do
    let(:incoming) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, source_id: 'WAID:IN1', content: 'Oi')
    end

    before do
      allow(api).to receive(:find_messages).with({ key: { id: 'IN1' } }, page: 1, offset: 1).and_return(
        { 'records' => [{ 'key' => { 'id' => 'IN1', 'remoteJid' => '5562999990001@s.whatsapp.net', 'fromMe' => false } }] }
      )
      allow(api).to receive(:send_reaction).and_return({})
    end

    it 'sends the reaction with the WhatsApp key of the message' do
      described_class.new(message: incoming, account_user: account_user).react('❤️')

      expect(api).to have_received(:send_reaction)
        .with(key: { 'id' => 'IN1', 'remoteJid' => '5562999990001@s.whatsapp.net', 'fromMe' => false }, reaction: '❤️')
    end

    it 'removes the company reaction, which Evolution does not send back' do
      mine = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: '❤️',
                              source_id: 'WAID:R1', content_attributes: { in_reply_to: incoming.id })

      described_class.new(message: incoming, account_user: account_user).react('')

      expect(mine.reload.content_attributes['outsider_reaction']).to eq({ 'emoji' => '❤️', 'removed' => true })
    end

    it 'refuses what is not a single emoji' do
      expect { described_class.new(message: incoming, account_user: account_user).react('ok') }
        .to raise_error(described_class::Invalid, 'invalid_emoji')
    end
  end
end
