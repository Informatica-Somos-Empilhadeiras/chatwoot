require 'rails_helper'
require 'vips'

RSpec.describe 'Outsider stickers', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/stickers" }
  let(:library) { Outsider::StickerLibrary.new(user: agent, account: account) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def png_upload(width = 300, height = 200)
    path = Rails.root.join('tmp', "sticker-spec-#{width}x#{height}-#{SecureRandom.hex(4)}.png").to_s
    Vips::Image.black(width, height).write_to_file(path)
    Rack::Test::UploadedFile.new(path, 'image/png')
  end

  def webp_io
    StringIO.new(Vips::Image.black(100, 100).webpsave_buffer)
  end

  def received_sticker
    message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: nil)
    message.attachments.create!(account_id: account.id, file_type: :image, file: { io: webp_io, filename: 'abc.webp', content_type: 'image/webp' })
  end

  describe 'POST create' do
    it 'turns an uploaded image into a 512x512 webp sticker of the agent' do
      post url, params: { file: png_upload }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      sticker = Outsider::Sticker.last
      expect(sticker.user_id).to eq(agent.id)
      expect(sticker.file.content_type).to eq('image/webp')
      size = sticker.file.blob.open { |file| Vips::Image.new_from_file(file.path).then { |image| [image.width, image.height] } }
      expect(size).to eq([512, 512])
      expect(response.parsed_body['existed']).to be(false)
    end

    it 'does not add the same image twice' do
      post url, params: { file: png_upload(120, 120) }, headers: agent.create_new_auth_token
      post url, params: { file: png_upload(120, 120) }, headers: agent.create_new_auth_token

      expect(response.parsed_body['existed']).to be(true)
      expect(Outsider::Sticker.count).to eq(1)
    end

    it 'saves a sticker received in a conversation the agent can see' do
      attachment = received_sticker

      post url, params: { attachment_id: attachment.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(Outsider::Sticker.last.source).to eq('received')
    end

    it 'refuses an attachment from a conversation the agent cannot see' do
      attachment = received_sticker

      post url, params: { attachment_id: attachment.id }, headers: other.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Outsider::Sticker.count).to eq(0)
    end

    it 'refuses files that are not images' do
      file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/attachment.pdf').to_s, 'application/pdf')

      post url, params: { file: file }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('file_type')
    end
  end

  describe 'GET index' do
    it 'lists only the own collection' do
      library.add_upload(png_upload(50, 50))
      Outsider::StickerLibrary.new(user: other, account: account).add_upload(png_upload(60, 60))

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['stickers'].size).to eq(1)
      expect(response.parsed_body['stickers'].first['url']).to include('/rails/active_storage/')
    end
  end

  describe 'POST send' do
    let(:sticker) { library.add_upload(png_upload(80, 80)).first }

    before { conversation.contact.update!(phone_number: '+5562999990000') }

    it 'sends through the Evolution API and marks the echoed message' do
      api = instance_double(Outsider::EvolutionApi)
      allow(Outsider::EvolutionApi).to receive(:new).and_return(api)
      allow(api).to receive(:send_sticker) do
        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, source_id: 'WAID:ABC', content: nil)
        { 'key' => { 'id' => 'ABC' } }
      end

      post "#{url}/#{sticker.id}/send", params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(api).to have_received(:send_sticker).with(number: '5562999990000', sticker: kind_of(String))
      echo = Message.find_by(source_id: 'WAID:ABC')
      expect(echo.sender).to eq(agent)
      expect(echo.content_attributes.dig('outsider_sticker', 'id')).to eq(sticker.id)
      expect(sticker.reload.uses_count).to eq(1)
    end

    it 'creates the message itself on the official API inbox' do
      cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      create(:inbox_member, user: agent, inbox: cloud.inbox)
      cloud_conversation = create(:conversation, account: account, inbox: cloud.inbox)

      post "#{url}/#{sticker.id}/send", params: { conversation_id: cloud_conversation.display_id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      message = cloud_conversation.messages.outgoing.last
      expect(message.attachments.first.file_type).to eq('image')
      expect(message.attachments.first.file.blob).to eq(sticker.file.blob)
      expect(message.content_attributes.dig('outsider_sticker', 'id')).to eq(sticker.id)
    end

    it 'refuses other channels' do
      widget = create(:channel_widget, account: account)
      create(:inbox_member, user: agent, inbox: widget.inbox)
      widget_conversation = create(:conversation, account: account, inbox: widget.inbox)

      post "#{url}/#{sticker.id}/send", params: { conversation_id: widget_conversation.display_id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('not_supported')
    end
  end

  describe 'packs and favorites' do
    it 'creates a pack, moves a sticker into it, favorites it and frees it when the pack goes' do
      sticker = library.add_upload(png_upload(70, 70)).first
      packs_url = "/api/v1/accounts/#{account.id}/outsider/sticker_packs"

      post packs_url, params: { name: '  Clientes  ' }, headers: agent.create_new_auth_token, as: :json
      pack_id = response.parsed_body.dig('pack', 'id')
      expect(response.parsed_body.dig('pack', 'name')).to eq('Clientes')

      patch "#{url}/#{sticker.id}", params: { pack_id: pack_id, favorite: true }, headers: agent.create_new_auth_token, as: :json
      expect(sticker.reload.pack_id).to eq(pack_id)
      expect(sticker.favorite).to be(true)

      delete "#{packs_url}/#{pack_id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(sticker.reload.pack_id).to be_nil
    end

    it 'does not touch another agent sticker' do
      sticker = Outsider::StickerLibrary.new(user: other, account: account).add_upload(png_upload(90, 90)).first

      patch "#{url}/#{sticker.id}", params: { favorite: true }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
