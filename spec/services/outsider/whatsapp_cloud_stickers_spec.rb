require 'rails_helper'
require 'vips'

RSpec.describe Outsider::WhatsappCloudStickers do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:service) { Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel) }

  def outgoing_message(content_attributes)
    message = create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, content: nil,
                               content_attributes: content_attributes)
    message.attachments.create!(account_id: account.id, file_type: :image,
                                file: { io: StringIO.new(Vips::Image.black(64, 64).webpsave_buffer), filename: 'f.webp', content_type: 'image/webp' })
    message.reload
  end

  it 'sends the sticker message with type sticker' do
    message = outgoing_message('outsider_sticker' => { 'id' => 1 })
    stub = stub_request(:post, %r{graph\.facebook\.com/v24\.0/.+/messages})
           .with(body: hash_including('type' => 'sticker', 'sticker' => hash_including('link' => a_string_including('/rails/active_storage/'))))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.send_message('+5562999990000', message)).to eq('wamid.1')
    expect(stub).to have_been_requested
  end

  it 'keeps plain images as image' do
    message = outgoing_message({})
    stub = stub_request(:post, %r{graph\.facebook\.com/v24\.0/.+/messages})
           .with(body: hash_including('type' => 'image'))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.2' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    service.send_message('+5562999990000', message)
    expect(stub).to have_been_requested
  end
end
