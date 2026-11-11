require 'rails_helper'

RSpec.describe 'Outsider transcrição no navegador', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil) }
  let(:attachment) do
    item = message.attachments.new(account_id: account.id, file_type: :audio)
    item.file.attach(io: StringIO.new('ogg bytes'), filename: 'audio.ogg', content_type: 'audio/ogg')
    item.save!
    item
  end
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/transcriptions" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'keeps the transcription where Chatwoot shows it, tells the conversation and lets only the author or an admin redo it' do
    post url, params: { attachment_id: attachment.id, text: "  Bom dia,  \n\n\n\n quero  a proposta ", engine: 'navegador', model: 'whisper-small',
                        language: 'pt', duration: 12.345 },
              headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['transcribed_text']).to eq("Bom dia,\n\nquero a proposta")
    attachment.reload
    expect(attachment.meta['transcribed_text']).to eq("Bom dia,\n\nquero a proposta")
    expect(attachment.meta['outsider_transcricao']).to include('by' => agent.id, 'engine' => 'navegador', 'model' => 'whisper-small',
                                                               'language' => 'pt', 'duration' => 12.3)
    expect(attachment.push_event_data[:transcribed_text]).to eq("Bom dia,\n\nquero a proposta")

    # texto vazio não vale; quem não vê a conversa não transcreve
    post url, params: { attachment_id: attachment.id, text: '   ' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post url, params: { attachment_id: attachment.id, text: 'oi' }, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    # apagar: outro agente não; quem transcreveu sim
    delete "#{url}/#{attachment.id}", headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    delete "#{url}/#{attachment.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(attachment.reload.meta).not_to include('transcribed_text')

    # administrador apaga o que outro transcreveu
    post url, params: { attachment_id: attachment.id, text: 'de novo' }, headers: agent.create_new_auth_token, as: :json
    delete "#{url}/#{attachment.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
  end

  it 'refuses files that are not audio or video' do
    image = message.attachments.new(account_id: account.id, file_type: :image)
    image.file.attach(io: StringIO.new('png'), filename: 'foto.png', content_type: 'image/png')
    image.save!
    post url, params: { attachment_id: image.id, text: 'nada' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('not_audio')
  end

  it 'stores the transcription of a Teams voice note in the attachment of the owner only' do
    link = Outsider::TeamsLink.create!(account: account, user: agent, ms_user_id: 'ms-agent', display_name: 'Agente', access_token: 't',
                                       refresh_token: 'r', token_expires_at: 1.hour.from_now)
    thread = link.threads.create!(kind: 'chat', chat_id: '19:chat', chat_type: 'oneOnOne', title: 'Ricardo')
    teams_message = thread.messages.create!(sender_name: 'Ricardo', content: '', sent_at: Time.current, graph_id: '1', status: 'sent',
                                            attachments: [{ 'kind' => 'file', 'name' => 'Recording 2.m4a',
                                                            'url' => 'https://x.sharepoint.com/r.m4a' }])
    teams_url = "#{url}/teams/#{teams_message.id}"
    allow(Outsider::Teams::Graph::Notifier).to receive(:message)

    post teams_url, params: { index: 0, text: 'Oi, pode me ligar?' }, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post teams_url, params: { index: 0, text: 'Oi, pode me ligar?', model: 'whisper-base' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(teams_message.reload.attachments.first).to include('transcript' => 'Oi, pode me ligar?')
    expect(teams_message.attachments.first['transcript_meta']).to include('by' => agent.id, 'model' => 'whisper-base')
    expect(Outsider::Teams::Graph::Notifier).to have_received(:message).with(link, thread, teams_message, action: 'updated')
    expect(Outsider::Teams::Graph::Json.message(teams_message)[:attachments].first).to include(transcript: 'Oi, pode me ligar?')

    post teams_url, params: { index: 3, text: 'x' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
