require 'rails_helper'

RSpec.describe Outsider::WhatsappReactorJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:group) { create(:contact, account: account, name: 'Equipe Obras', identifier: '120363000000000000@g.us') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: group) }
  let(:original) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi') }
  let(:reaction) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: '🙏',
                     source_id: 'WAID:REACT', content_attributes: { in_reply_to: original.id })
  end
  let(:api) { instance_double(Outsider::EvolutionApi) }

  before { allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api) }

  def found(record)
    allow(api).to receive(:find_messages).with({ key: { id: 'REACT' } }, page: 1, offset: 1).and_return({ 'records' => [record].compact })
  end

  it 'stores the group participant who reacted' do
    found({ 'messageType' => 'reactionMessage', 'pushName' => 'Ana', 'key' => { 'participant' => '5562999990002@s.whatsapp.net' } })

    described_class.perform_now(reaction.id)

    expect(reaction.reload.content_attributes['outsider_reaction']).to eq(
      { 'emoji' => '🙏', 'from' => { 'jid' => '5562999990002@s.whatsapp.net', 'name' => 'Ana', 'phone' => '5562999990002' } }
    )
  end

  it 'prefers the phone number when WhatsApp sends the participant as a LID' do
    found({ 'messageType' => 'reactionMessage', 'pushName' => 'Bruno',
            'key' => { 'participant' => '123456789@lid', 'participantAlt' => '5562999990003@s.whatsapp.net' } })

    described_class.perform_now(reaction.id)

    expect(reaction.reload.content_attributes.dig('outsider_reaction', 'from', 'phone')).to eq('5562999990003')
  end

  it 'turns the message back into a normal one when it was a reply with an emoji' do
    found({ 'messageType' => 'extendedTextMessage', 'key' => {} })

    described_class.perform_now(reaction.id)

    expect(reaction.reload.content_attributes['outsider_reaction']).to be_nil
  end

  it 'tries again while Evolution has not saved the reaction yet' do
    found(nil)
    id = reaction.id

    expect { described_class.perform_now(id) }.to have_enqueued_job(described_class).with(id)
  end
end
