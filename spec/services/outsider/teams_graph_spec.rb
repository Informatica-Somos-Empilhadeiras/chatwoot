require 'rails_helper'

RSpec.describe 'Outsider Conectar meu Teams (Microsoft Graph)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:tenant) { 'a81d44f0-1111-2222-3333-44445555c9e0' }
  let(:client_id) { '3f2a9c1e-aaaa-bbbb-cccc-dddddddd77b0' }
  let(:graph_app) do
    Outsider::TeamsGraphApp.create!(account: account, client_id: client_id, tenant_id: tenant, client_secret: 'segredo-do-app')
  end
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:link) do
    Outsider::TeamsLink.create!(account: account, user: agent, ms_user_id: 'ms-agent', display_name: 'Agente Teams',
                                access_token: 'token-agente', refresh_token: 'refresh-agente', token_expires_at: 1.hour.from_now,
                                channels: [{ 'team_id' => 'team-1', 'team_name' => 'Comercial', 'channel_id' => '19:canal@thread.tacv2',
                                             'channel_name' => 'Propostas' }])
  end

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chat.exemplo.com.br') { example.run }
  end

  def graph_json(body = nil, status: 200, **fields)
    { status: status, body: (body || fields).to_json, headers: json_headers }
  end

  it 'logs a person in with the Microsoft account and asks Microsoft for message notices' do
    graph_app
    get "/api/v1/accounts/#{account.id}/outsider/teams_graph", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('configured' => true, 'admin' => false, 'app' => nil, 'me' => nil, 'links' => [])

    post "/api/v1/accounts/#{account.id}/outsider/teams_graph/authorize", headers: agent.create_new_auth_token, as: :json
    url = URI.parse(response.parsed_body['url'])
    query = Rack::Utils.parse_query(url.query)
    expect(url.host).to eq('login.microsoftonline.com')
    expect(url.path).to eq("/#{tenant}/oauth2/v2.0/authorize")
    expect(query).to include('client_id' => client_id, 'redirect_uri' => 'https://chat.exemplo.com.br/outsider/teams/oauth/callback')
    expect(query['scope']).to include('offline_access', 'Chat.ReadWrite', 'ChannelMessage.Read.All')

    get '/outsider/teams/oauth/callback', params: { code: 'codigo-1', state: query['state'] }
    expect(response).to redirect_to(%r{\Ahttps://chat.exemplo.com.br/app/accounts/#{account.id}/settings/outsider/teams\?teams_oauth})

    token = stub_request(:post, "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token")
            .with(body: hash_including('grant_type' => 'authorization_code', 'code' => 'codigo-1', 'client_secret' => 'segredo-do-app'))
            .to_return(graph_json(access_token: 'novo-token', refresh_token: 'novo-refresh', expires_in: 3600))
    stub_request(:get, %r{graph.microsoft.com/v1.0/me}).to_return(graph_json(id: 'ms-agent', displayName: 'Agente Teams',
                                                                             userPrincipalName: 'agente@empresa.com'))
    subscribe = stub_request(:post, 'https://graph.microsoft.com/beta/subscriptions')
                .with(body: hash_including('resource' => '/users/ms-agent/chats/getAllMessages', 'changeType' => 'created,updated,deleted',
                                           'notificationUrl' => 'https://chat.exemplo.com.br/outsider/teams/graph/notifications'))
                .to_return(graph_json(id: 'sub-chats', expirationDateTime: 2.days.from_now.iso8601))

    # o state de outra pessoa não serve
    post "/api/v1/accounts/#{account.id}/outsider/teams_graph/finish",
         params: { code: 'codigo-1', state: query['state'] }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post "/api/v1/accounts/#{account.id}/outsider/teams_graph/finish",
         params: { code: 'codigo-1', state: query['state'] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(token).to have_been_requested
    expect(subscribe).to have_been_requested
    created = Outsider::TeamsLink.find_by!(user: agent)
    expect(created).to have_attributes(ms_user_id: 'ms-agent', email: 'agente@empresa.com', status: 'active', access_token: 'novo-token',
                                       refresh_token: 'novo-refresh')
    expect(created.subscriptions.sole).to have_attributes(kind: 'chats', subscription_id: 'sub-chats')
    expect(created.access_token_encrypted).not_to include('novo-token')

    # a mesma conta Microsoft não liga em outra pessoa
    outro = Outsider::Teams::Graph::Connect.new(graph_app, admin)
    expect { outro.perform('codigo-1') }.to raise_error(Outsider::Teams::Graph::Connect::Error, /already_linked/)
  end

  it 'lets only administrators register the company app and see who is connected, never the conversations' do
    put "/api/v1/accounts/#{account.id}/outsider/teams_graph/app",
        params: { client_id: client_id, tenant_id: tenant, client_secret: 'x' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    put "/api/v1/accounts/#{account.id}/outsider/teams_graph/app",
        params: { client_id: client_id.upcase, tenant_id: tenant, client_secret: 's1' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(Outsider::TeamsGraphApp.find_by(account: account)).to have_attributes(client_id: client_id, client_secret: 's1')

    post "/api/v1/accounts/#{account.id}/outsider/teams_graph/consent", headers: admin.create_new_auth_token, as: :json
    consent = URI.parse(response.parsed_body['url'])
    expect(consent.path).to eq("/#{tenant}/v2.0/adminconsent")
    state = Rack::Utils.parse_query(consent.query)['state']
    post "/api/v1/accounts/#{account.id}/outsider/teams_graph/finish",
         params: { admin_consent: 'True', state: state }, headers: admin.create_new_auth_token, as: :json
    expect(Outsider::TeamsGraphApp.find_by(account: account).consent_granted_at).to be_present

    thread = link.threads.create!(kind: 'chat', chat_id: '19:chat', title: 'Ricardo', unread_count: 1)
    get "/api/v1/accounts/#{account.id}/outsider/teams_graph", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['links'].sole).to include('user_name' => agent.name, 'channels_count' => 1, 'status' => 'active')

    get "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{account.id}/outsider/teams_threads", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq([])
    get "/api/v1/accounts/#{account.id}/outsider/teams_threads/summary", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('connected' => true, 'unread_chats' => 1, 'unread_channels' => 0)
  end

  it 'accepts Microsoft notices only with the subscription secret and answers the validation' do
    subscription = link.subscriptions.create!(kind: 'chats', resource: '/users/ms-agent/chats/getAllMessages', subscription_id: 'sub-1')

    post '/outsider/teams/graph/notifications?validationToken=abc%20123'
    expect(response.body).to eq('abc 123')
    expect(response.media_type).to eq('text/plain')

    notice = { value: [{ subscriptionId: 'sub-1', clientState: 'errado', changeType: 'created',
                         resource: "chats('19:chat')/messages('111')" }] }
    expect do
      post '/outsider/teams/graph/notifications', params: notice.to_json, headers: json_headers
    end.not_to have_enqueued_job(Outsider::Teams::Graph::ReceiveJob)
    expect(response).to have_http_status(:accepted)

    notice[:value][0][:clientState] = subscription.client_state
    expect do
      post '/outsider/teams/graph/notifications', params: notice.to_json, headers: json_headers
    end.to have_enqueued_job(Outsider::Teams::Graph::ReceiveJob).with(subscription.id, "chats('19:chat')/messages('111')", 'created')
  end

  it 'brings a 1:1 chat message into the owner area once, keeping only where the files are, and sends the answer as the person' do
    html_body = '<p>Olá <at id="0">André</at>,&nbsp;segue a nota <emoji alt="👍"></emoji></p>' \
                '<img src="https://graph.microsoft.com/v1.0/chats/x/messages/111/hostedContents/aa/$value">'
    stub_request(:get, 'https://graph.microsoft.com/v1.0/chats/19%3Achat%40unq.gbl.spaces/messages/111')
      .to_return(graph_json(id: '111', messageType: 'message', createdDateTime: '2026-11-08T09:41:00Z',
                            from: { user: { id: 'ms-ricardo', displayName: 'Ricardo Mendes' } },
                            body: { contentType: 'html', content: html_body },
                            mentions: [{ id: 0, mentionText: 'André', mentioned: { user: { id: 'ms-agent', displayName: 'André' } } }],
                            attachments: [{ contentType: 'reference', name: 'NF.pdf', contentUrl: 'https://empresa-my.sharepoint.com/nf.pdf' }]))
    stub_request(:get, %r{graph.microsoft.com/v1.0/chats/19:chat@unq.gbl.spaces\?})
      .to_return(graph_json(chatType: 'oneOnOne', members: [{ userId: 'ms-agent', displayName: 'Agente' },
                                                            { userId: 'ms-ricardo', displayName: 'Ricardo Mendes' }]))

    ref = Outsider::Teams::Graph::Inbound.parse("chats('19:chat@unq.gbl.spaces')/messages('111')")
    message = Outsider::Teams::Graph::Inbound.new(link, ref).perform
    expect(message).to have_attributes(mine: false, sender_name: 'Ricardo Mendes', content: 'Olá @André, segue a nota 👍', mentions_me: true)
    expect(message.attachments).to eq([
                                        { 'kind' => 'file', 'name' => 'NF.pdf', 'url' => 'https://empresa-my.sharepoint.com/nf.pdf',
                                          'source' => 'onedrive' },
                                        { 'kind' => 'image', 'name' => 'imagem-1.png', 'source' => 'teams',
                                          'hosted' => 'https://graph.microsoft.com/v1.0/chats/x/messages/111/hostedContents/aa/$value' }
                                      ])
    expect(ActiveStorage::Attachment.count).to eq(0)
    expect(message.thread).to have_attributes(kind: 'chat', title: 'Ricardo Mendes', unread_count: 1, mention_count: 1,
                                              last_message_preview: 'Olá @André, segue a nota 👍')
    expect(Outsider::Teams::Graph::Inbound.new(link, ref).perform.id).to eq(message.id)
    expect(Outsider::TeamsMessage.count).to eq(1)

    get "/api/v1/accounts/#{account.id}/outsider/teams_threads?kind=chat", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].sole).to include('title' => 'Ricardo Mendes', 'unread_count' => 1, 'mention_count' => 1)

    sent = stub_request(:post, 'https://graph.microsoft.com/v1.0/chats/19%3Achat%40unq.gbl.spaces/messages')
           .with(headers: { 'Authorization' => 'Bearer token-agente' },
                 body: { body: { contentType: 'html', content: 'Vou ver &lt;já&gt;<br>obrigado' } }.to_json)
           .to_return(graph_json(id: '222', createdDateTime: '2026-11-08T09:45:00Z', status: 201))
    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{message.thread_id}/messages",
         params: { content: "Vou ver <já>\nobrigado" }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    reply = Outsider::TeamsMessage.find(response.parsed_body['id'])
    perform_enqueued_jobs(only: Outsider::Teams::Graph::SendJob)
    expect(sent).to have_been_requested
    expect(reply.reload).to have_attributes(graph_id: '222', status: 'sent', mine: true)

    # o aviso da Microsoft sobre a própria resposta não duplica
    stub_request(:get, 'https://graph.microsoft.com/v1.0/chats/19%3Achat%40unq.gbl.spaces/messages/222')
      .to_return(graph_json(id: '222', messageType: 'message', from: { user: { id: 'ms-agent' } }, body: { content: 'Vou ver' }))
    Outsider::Teams::Graph::Inbound.new(link, Outsider::Teams::Graph::Inbound.parse("chats('19:chat@unq.gbl.spaces')/messages('222')")).perform
    expect(Outsider::TeamsMessage.count).to eq(2)

    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{message.thread_id}/read", headers: agent.create_new_auth_token, as: :json
    expect(message.thread.reload).to have_attributes(unread_count: 0, mention_count: 0, last_read_at: be_present)
  end

  it 'shows Teams files live from Microsoft (thumbnail, preview, download) without storing them' do
    thread = link.threads.create!(kind: 'chat', chat_id: '19:chat', chat_type: 'oneOnOne', title: 'Ricardo')
    message = thread.messages.create!(graph_id: '111', sender_name: 'Ricardo', sent_at: Time.current, attachments: [
                                        { 'kind' => 'file', 'name' => 'Proposta.docx',
                                          'url' => 'https://empresa.sharepoint.com/sites/x/Proposta.docx' },
                                        { 'kind' => 'image', 'name' => 'imagem-1.png',
                                          'hosted' => 'https://graph.microsoft.com/v1.0/chats/x/hostedContents/aa/$value' }
                                      ])
    share = Outsider::Teams::Graph::Files.share_id('https://empresa.sharepoint.com/sites/x/Proposta.docx')
    resolve = stub_request(:get, %r{graph.microsoft.com/v1.0/shares/#{Regexp.escape(share)}/driveItem})
              .to_return(graph_json(id: 'item-1', name: 'Proposta.docx', size: 2048, webUrl: 'https://empresa.sharepoint.com/:w:/r/Proposta',
                                    parentReference: { driveId: 'drive-1' }))
    stub_request(:post, 'https://graph.microsoft.com/v1.0/drives/drive-1/items/item-1/preview')
      .to_return(graph_json(getUrl: 'https://empresa.sharepoint.com/embed?token=1'))
    stub_request(:get, %r{graph.microsoft.com/v1.0/drives/drive-1/items/item-1\?})
      .to_return(graph_json('@microsoft.graph.downloadUrl' => 'https://empresa.sharepoint.com/download.aspx?tempauth=x'))
    stub_request(:get, 'https://graph.microsoft.com/v1.0/chats/x/hostedContents/aa/$value')
      .with(headers: { 'Authorization' => 'Bearer token-agente' })
      .to_return(status: 200, body: 'png-bytes', headers: { 'Content-Type' => 'image/png' })

    get "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages", headers: agent.create_new_auth_token, as: :json
    file, image = response.parsed_body['payload'].sole['attachments']
    expect(file).to include('kind' => 'file', 'extension' => 'docx', 'edit_url' => 'https://empresa.sharepoint.com/sites/x/Proposta.docx')

    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages/#{message.id}/attachments/0/preview",
         headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('kind' => 'preview', 'view_url' => 'https://empresa.sharepoint.com/embed?token=1&nb=true',
                                            'edit_url' => 'https://empresa.sharepoint.com/:w:/r/Proposta')
    expect(message.reload.attachments.first).to include('drive_id' => 'drive-1', 'item_id' => 'item-1', 'size' => 2048)

    get file['download_url']
    expect(response).to redirect_to('https://empresa.sharepoint.com/download.aspx?tempauth=x')
    get image['thumb_url']
    expect(response.body).to eq('png-bytes')
    expect(response.media_type).to eq('image/png')
    expect(resolve).to have_been_requested.once
    get "#{file['download_url']}x"
    expect(response).to have_http_status(:not_found)

    # a área dos outros continua fechada
    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages/#{message.id}/attachments/0/preview",
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it 'quotes in chats, mentions people and sends files through OneDrive' do
    thread = link.threads.create!(kind: 'chat', chat_id: '19:chat', chat_type: 'group', title: 'Vendas',
                                  members: [{ 'id' => 'ms-agent', 'name' => 'Agente Teams' }, { 'id' => 'ms-ana', 'name' => 'Ana Paula' },
                                            { 'id' => 'ms-ana2', 'name' => 'Ana' }])
    quoted = thread.messages.create!(graph_id: '500', sender_name: 'Ana Paula', content: 'Preço da EFX-25?', sent_at: 1.minute.ago)

    get "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/members", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('name')).to eq(['Ana', 'Ana Paula'])

    upload = stub_request(:put, %r{graph.microsoft.com/v1.0/me/drive/root:/Microsoft%20Teams%20Chat%20Files/tabela.pdf:/content})
             .to_return(graph_json(id: 'item-9', name: 'tabela.pdf', size: 4, eTag: '"{8D2F0A1B-1111-2222-3333-444455556666},1"',
                                   webUrl: 'https://empresa-my.sharepoint.com/:b:/tabela', webDavUrl: 'https://empresa-my.sharepoint.com/tabela.pdf',
                                   parentReference: { driveId: 'drive-me' }))
    invite = stub_request(:post, 'https://graph.microsoft.com/v1.0/drives/drive-me/items/item-9/invite')
             .with(body: hash_including('recipients' => [{ 'objectId' => 'ms-ana' }, { 'objectId' => 'ms-ana2' }], 'sendInvitation' => false))
             .to_return(graph_json(value: []))
    answer = stub_request(:post, 'https://graph.microsoft.com/v1.0/chats/19%3Achat/messages/replyWithQuote')
             .with(body: hash_including('messageIds' => ['500']))
             .to_return(graph_json(id: '501'))

    file = Rack::Test::UploadedFile.new(StringIO.new('%PDF'), 'application/pdf', original_filename: 'tabela.pdf')
    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages",
         params: { content: '@Ana Paula segue, e @Ana confere', quote_id: quoted.id, attachments: [file] },
         headers: agent.create_new_auth_token
    expect(response).to have_http_status(:created)
    expect(upload).to have_been_requested
    expect(invite).to have_been_requested
    expect(response.parsed_body['quote']).to include('graph_id' => '500', 'sender' => 'Ana Paula', 'text' => 'Preço da EFX-25?')

    perform_enqueued_jobs(only: Outsider::Teams::Graph::SendJob)
    expect(answer).to have_been_requested
    body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find { |sig| sig.uri.path.end_with?('replyWithQuote') }.body)
    message = body['replyMessage']
    expect(message['body']['content']).to eq('<at id="0">Ana Paula</at> segue, e <at id="1">Ana</at> confere<br>' \
                                             '<attachment id="8d2f0a1b-1111-2222-3333-444455556666"></attachment>')
    expect(message['mentions'].pluck('mentionText')).to eq(['Ana Paula', 'Ana'])
    expect(message['attachments'].sole).to include('contentType' => 'reference', 'name' => 'tabela.pdf',
                                                   'contentUrl' => 'https://empresa-my.sharepoint.com/tabela.pdf')
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it 'keeps channel replies under their post and replies inside the post' do
    base = 'https://graph.microsoft.com/v1.0/teams/team-1/channels/19%3Acanal%40thread.tacv2/messages'
    stub_request(:get, "#{base}/900").to_return(graph_json(id: '900', messageType: 'message', subject: 'Proposta Transportadora',
                                                           from: { user: { id: 'ms-juliana', displayName: 'Juliana Nogueira' } },
                                                           body: { contentType: 'text', content: 'Alguém aprova 5%?' }))
    stub_request(:get, "#{base}/900/replies/901").to_return(graph_json(id: '901', replyToId: '900', messageType: 'message',
                                                                       from: { user: { id: 'ms-ricardo', displayName: 'Ricardo' } },
                                                                       body: { contentType: 'text', content: 'Até 4%' }))
    post_ref = Outsider::Teams::Graph::Inbound.parse("teams('team-1')/channels('19:canal@thread.tacv2')/messages('900')")
    reply_ref = Outsider::Teams::Graph::Inbound.parse("teams('team-1')/channels('19:canal@thread.tacv2')/messages('900')/replies('901')")
    expect(reply_ref).to include(kind: 'channel', message_id: '901', parent_id: '900')
    Outsider::Teams::Graph::Inbound.new(link, post_ref).perform
    Outsider::Teams::Graph::Inbound.new(link, reply_ref).perform

    thread = link.threads.sole
    expect(thread).to have_attributes(kind: 'channel', title: 'Propostas', team_name: 'Comercial', unread_count: 2,
                                      last_message_preview: 'Ricardo: Até 4%')
    get "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages", headers: agent.create_new_auth_token, as: :json
    post_json = response.parsed_body['payload'].sole
    expect(post_json).to include('subject' => 'Proposta Transportadora', 'content' => 'Alguém aprova 5%?')
    expect(post_json['replies'].sole).to include('content' => 'Até 4%', 'reply_to_graph_id' => '900')

    # modo Conversa: tudo em sequência, a resposta mostra a publicação; citação feita no Teams vem junto
    reference = { messageId: '901', messagePreview: 'Até 4%', messageSender: { user: { displayName: 'Ricardo' } } }
    channel_mention = { id: 0, mentioned: { conversation: { id: '19:canal', conversationIdentityType: 'channel' } } }
    stub_request(:get, "#{base}/900/replies/905")
      .to_return(graph_json(id: '905', replyToId: '900', messageType: 'message', mentions: [channel_mention],
                            from: { user: { id: 'ms-juliana', displayName: 'Juliana Nogueira' } },
                            body: { contentType: 'html', content: '<attachment id="901"></attachment><p>Ok, 4%</p>' },
                            attachments: [{ id: '901', contentType: 'messageReference', content: reference.to_json }]))
    quoted_ref = Outsider::Teams::Graph::Inbound.parse("teams('team-1')/channels('19:canal@thread.tacv2')/messages('900')/replies('905')")
    Outsider::Teams::Graph::Inbound.new(link, quoted_ref).perform
    get "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages?mode=flat", headers: agent.create_new_auth_token, as: :json
    flat = response.parsed_body['payload']
    expect(flat.pluck('content')).to eq(['Alguém aprova 5%?', 'Até 4%', 'Ok, 4%'])
    expect(flat[1]['quote']).to include('sender' => 'Juliana Nogueira', 'text' => 'Proposta Transportadora', 'post' => true)
    expect(flat[2]).to include('mentions_me' => true, 'quote' => { 'graph_id' => '901', 'sender' => 'Ricardo', 'text' => 'Até 4%' })
    expect(thread.reload.members.pluck('name')).to include('Juliana Nogueira', 'Ricardo')

    answer = stub_request(:post, "#{base}/900/replies").to_return(graph_json(id: '902'))
    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/messages",
         params: { content: 'Fechado em 4%', reply_to_graph_id: '900' }, headers: agent.create_new_auth_token, as: :json
    perform_enqueued_jobs(only: Outsider::Teams::Graph::SendJob)
    expect(answer).to have_been_requested

    # canal que a pessoa tirou da lista não recebe mais
    link.update!(channels: [])
    expect(Outsider::Teams::Graph::ReceiveJob.new.perform(link.subscriptions.create!(kind: 'chats', resource: 'x').id,
                                                          "teams('team-1')/channels('19:canal@thread.tacv2')/messages('903')")).to be_nil
  end

  it 'renews the token, asks the person to sign in again when Microsoft refuses, and renews notices before they expire' do
    graph_app
    link.update!(token_expires_at: 1.minute.from_now)
    stub_request(:post, "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token")
      .with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => 'refresh-agente'))
      .to_return(graph_json(access_token: 'token-2', refresh_token: 'refresh-2', expires_in: 3600))
    expect(Outsider::Teams::Graph::Client.new(link).token).to eq('token-2')
    expect(link.reload).to have_attributes(access_token: 'token-2', refresh_token: 'refresh-2')

    subscription = link.subscriptions.create!(kind: 'chats', resource: '/users/ms-agent/chats/getAllMessages', subscription_id: 'sub-1',
                                              expires_at: 2.hours.from_now)
    fresh = link.subscriptions.create!(kind: 'channel', team_id: 't', channel_id: 'c', resource: '/teams/t/channels/c/messages',
                                       subscription_id: 'sub-2', expires_at: 3.days.from_now)
    renew = stub_request(:patch, 'https://graph.microsoft.com/beta/subscriptions/sub-1')
            .to_return(graph_json(id: 'sub-1', expirationDateTime: 3.days.from_now.iso8601))
    Outsider::Teams::Graph::RenewJob.new.perform
    expect(renew).to have_been_requested
    expect(subscription.reload.expires_at).to be > 2.days.from_now
    expect(fresh.reload.expires_at).to be > 2.days.from_now

    link.update!(token_expires_at: 1.minute.ago)
    stub_request(:post, "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token")
      .to_return(graph_json({ error: 'invalid_grant', error_description: 'AADSTS50173: senha trocada' }, status: 400))
    expect { Outsider::Teams::Graph::Client.new(link).get('/me') }.to raise_error(Outsider::Teams::Graph::Client::Reconnect)
    expect(link.reload.status).to eq('reconnect')
  end
end
