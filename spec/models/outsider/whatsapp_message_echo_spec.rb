require 'rails_helper'

RSpec.describe Outsider::WhatsappMessageEcho do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let!(:original) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, source_id: 'WAID:ORIG',
                     content: 'Qual o prazo de entrega?')
  end

  def echo(content, **attrs)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content,
                       source_id: 'WAID:NEW', content_attributes: { in_reply_to: original.id } }.merge(attrs))
  end

  it 'marks a single emoji answering a message as a reaction' do
    expect(echo('👍').content_attributes['outsider_reaction']).to eq({ 'emoji' => '👍' })
    expect(echo('👍🏽').content_attributes['outsider_reaction']).to eq({ 'emoji' => '👍🏽' })
    expect(echo('😂😂').content_attributes['outsider_reaction']).to be_nil
    expect(echo('ok 👍').content_attributes['outsider_reaction']).to be_nil
    expect(echo('👍', content_attributes: {}).content_attributes['outsider_reaction']).to be_nil
  end

  it 'leaves inboxes that are not Evolution alone' do
    channel.update!(webhook_url: 'https://example.com/hook')

    expect(echo('👍').content_attributes['outsider_reaction']).to be_nil
  end

  it 'looks up who reacted only in group conversations' do
    expect { echo('❤️') }.not_to have_enqueued_job(Outsider::WhatsappReactorJob)

    customer.update!(identifier: '120363000000000000@g.us')
    expect { echo('❤️') }.to have_enqueued_job(Outsider::WhatsappReactorJob)
  end

  it 'moves an edit from WhatsApp into the original message and hides the Evolution copy' do
    copy = echo("\n\n`Mensagem editada:`\n\nQual o prazo de entrega para Goiânia?", source_id: 'WAID:ORIG')

    expect(copy.content_attributes['outsider_edit_of']).to eq(original.id)
    expect(original.reload.content).to eq('Qual o prazo de entrega para Goiânia?')
    expect(original.content_attributes['outsider_edited_at']).to be_present
  end

  it 'keeps the sender header of group messages when they are edited' do
    original.update!(content: "**+55 62 99999-0002 - Ana:**\n\nBom dia")

    echo("\n\n`Edited Message:`\n\nBom dia a todos", source_id: 'WAID:ORIG')

    expect(original.reload.content).to eq("**+55 62 99999-0002 - Ana:**\n\nBom dia a todos")
  end

  it 'does not touch a message already edited from Chatwoot' do
    original.update!(content: 'Entrega em 5 dias', content_attributes: { 'outsider_edit_sent' => "*Daniel:*\nEntrega em 5 dias" })

    copy = echo("\n\n`Mensagem editada:`\n\n*Daniel:*\nEntrega em 5 dias", source_id: 'WAID:ORIG', message_type: :outgoing)

    expect(copy.content_attributes['outsider_edit_of']).to eq(original.id)
    expect(original.reload.content).to eq('Entrega em 5 dias')
    expect(original.content_attributes['outsider_edited_at']).to be_nil
  end
end
