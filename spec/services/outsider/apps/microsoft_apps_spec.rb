require 'rails_helper'

RSpec.describe 'Outsider Aplicativos Microsoft (Outlook e OneDrive)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:graph) { 'https://graph.microsoft.com/v1.0' }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/apps/microsoft" }
  let(:scope_version) { 4 }
  let(:link) do
    Outsider::TeamsLink.create!(account: account, user: agent, ms_user_id: 'ms-agent', display_name: 'Agente', email: 'agente@empresa.com',
                                access_token: 'token-agente', refresh_token: 'refresh-agente', token_expires_at: 1.hour.from_now,
                                scope_version: scope_version)
  end

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chat.exemplo.com.br') { example.run }
  end

  before do
    Rails.cache.clear
    link
  end

  def graph_json(body = nil, status: 200, **fields)
    { status: status, body: (body || fields).to_json, headers: json_headers }
  end

  def auth
    agent.create_new_auth_token
  end

  it 'lists folders with the well-known ones first and the inbox messages, 25 per page' do
    stub_request(:post, "#{graph}/$batch").to_return(graph_json(responses: [
                                                                  { id: 'inbox', status: 200, body: { id: 'F-IN' } },
                                                                  { id: 'sentitems', status: 200, body: { id: 'F-SENT' } }
                                                                ]))
    stub_request(:get, %r{#{graph}/me/mailFolders\?}).to_return(graph_json(value: [
                                                                             { id: 'F-X', displayName: 'Clientes', unreadItemCount: 0,
                                                                               totalItemCount: 3 },
                                                                             { id: 'F-SENT', displayName: 'Itens Enviados', unreadItemCount: 0,
                                                                               totalItemCount: 9 },
                                                                             { id: 'F-IN', displayName: 'Caixa de Entrada', unreadItemCount: 2,
                                                                               totalItemCount: 40 }
                                                                           ]))
    get "#{base}/mail/folders", headers: auth, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('kind')).to eq(%w[inbox sentitems custom])

    list = stub_request(:get, %r{#{graph}/me/mailFolders/F-IN/messages}).with(query: hash_including('$top' => '25'))
                                                                        .to_return(graph_json(value: [
                                                                                                { id: 'M1', subject: 'Orçamento', isRead: false, hasAttachments: true,
                                                                                                  from: { emailAddress: { name: 'Cliente', address: 'cli@x.com' } },
                                                                                                  receivedDateTime: '2026-11-24T12:00:00Z', bodyPreview: 'Bom dia' }
                                                                                              ], '@odata.nextLink': "#{graph}/me/mailFolders/F-IN/messages?$skip=25"))
    get "#{base}/mail/messages", params: { folder: 'F-IN', filter: 'unread' }, headers: auth
    expect(list).to have_been_requested
    body = response.parsed_body
    expect(body['items'].first).to include('id' => 'M1', 'unread' => true, 'has_attachments' => true,
                                           'from' => { 'name' => 'Cliente', 'email' => 'cli@x.com' })
    expect(body['next']).to include('$skip=25')
    expect(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |r| r.uri.query_values }.compact.last['$filter'])
      .to include('isRead eq false')

    get "#{base}/mail/messages", params: { cursor: 'https://evil.example.com/me/x' }, headers: auth
    expect(response.parsed_body['error']).to eq('invalid')
  end

  it 'opens a message, marks it read, cleans the html, links inline images and finds the contact' do
    contact = create(:contact, account: account, email: 'cli@x.com', name: 'Cliente X')
    stub_request(:get, %r{#{graph}/me/messages/M1\?}).to_return(graph_json(
                                                                  id: 'M1', subject: 'Orçamento', isRead: false, hasAttachments: true,
                                                                  from: { emailAddress: { name: 'Cliente', address: 'cli@x.com' } },
                                                                  toRecipients: [{ emailAddress: { name: 'Eu', address: 'agente@empresa.com' } }],
                                                                  body: { contentType: 'html', content: '<html><body><p onclick="x()">Oi</p><script>alert(1)</script>' \
                                                                                                        '<img src="cid:image001.png@01DA"><a href="https://a.com">a</a></body></html>' }
                                                                ))
    read = stub_request(:patch, "#{graph}/me/messages/M1").with(body: { isRead: true }.to_json).to_return(graph_json(id: 'M1'))
    stub_request(:get, %r{#{graph}/me/messages/M1/attachments\?}).to_return(graph_json(value: [
                                                                                         { id: 'A1', name: 'image001.png', contentType: 'image/png',
                                                                                           size: 10, isInline: true },
                                                                                         { id: 'A2', name: 'proposta.pdf', contentType: 'application/pdf',
                                                                                           size: 2000, isInline: false }
                                                                                       ]))
    get "#{base}/mail/messages/M1", headers: auth
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(read).to have_been_requested
    expect(body['html']).not_to include('<script', 'onclick')
    expect(body['html']).to include('/outsider/apps/file?t=', 'target="_blank"')
    expect(body['attachments'].pluck('name')).to eq(['proposta.pdf'])
    expect(body['chatwoot']).to include('contact_id' => contact.id)

    # o anexo pelo endereço assinado, aos pedaços, sem sessão
    stub_request(:get,
                 %r{#{graph}/me/messages/M1/attachments/A2\?}).to_return(graph_json(id: 'A2', name: 'proposta.pdf', contentType: 'application/pdf',
                                                                                    size: 4))
    stub_request(:get, "#{graph}/me/messages/M1/attachments/A2/$value").to_return(status: 200, body: '%PDF')
    get body['attachments'].first['url']
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('inline', 'proposta.pdf')
    expect(response.body).to eq('%PDF')

    get '/outsider/apps/file', params: { t: 'falso' }
    expect(response.status).to eq(410)
  end

  it 'replies with the quoted original and attachments, and sends a new e-mail' do
    stub_request(:post,
                 "#{graph}/me/messages/M1/createReply").to_return(graph_json(id: 'D1',
                                                                             body: { content: '<html><body><p>original</p></body></html>' }))
    patch = stub_request(:patch, "#{graph}/me/messages/D1").with do |request|
      content = JSON.parse(request.body).dig('body', 'content')
      content.include?('Linha 1<br>&lt;b&gt;') && content.index('Linha 1') < content.index('original')
    end.to_return(graph_json(id: 'D1'))
    attach = stub_request(:post, "#{graph}/me/messages/D1/attachments").to_return(graph_json(id: 'AT'))
    send = stub_request(:post, "#{graph}/me/messages/D1/send").to_return(status: 202, body: '')

    file = Rack::Test::UploadedFile.new(StringIO.new('conteudo'), 'text/plain', original_filename: 'nota.txt')
    post "#{base}/mail/messages", params: { mode: 'reply', source_id: 'M1', text: "Linha 1\n<b>", files: [file] }, headers: auth
    expect(response).to have_http_status(:created)
    expect([patch, attach, send]).to all(have_been_requested)

    post "#{base}/mail/messages", params: { mode: 'new', text: 'oi' }, headers: auth, as: :json
    expect(response.parsed_body['error']).to eq('no_recipient')

    stub_request(:post, "#{graph}/me/messages").to_return(graph_json(id: 'D2', body: { content: '' }))
    new_patch = stub_request(:patch, "#{graph}/me/messages/D2").with do |request|
      JSON.parse(request.body)['toRecipients'] == [{ 'emailAddress' => { 'address' => 'cli@x.com' } }]
    end.to_return(graph_json(id: 'D2'))
    stub_request(:post, "#{graph}/me/messages/D2/send").to_return(status: 202, body: '')
    post "#{base}/mail/messages", params: { mode: 'new', to: 'cli@x.com, nao-email', subject: 'Oi', text: 'oi' }, headers: auth, as: :json
    expect(response).to have_http_status(:created)
    expect(new_patch).to have_been_requested
  end

  context 'with the permissions of before (version 3)' do
    let(:scope_version) { 3 }

    it 'asks to sign in again for Outlook but keeps OneDrive and the summary working' do
      get "#{base}/mail/folders", headers: auth, as: :json
      expect(response.parsed_body['error']).to eq('scope_outdated')

      stub_request(:get, %r{#{graph}/me/drive/root/children}).to_return(graph_json(value: [
                                                                                     { id: 'I2', name: 'b.pdf', size: 10, file: { mimeType: 'application/pdf' },
                                                                                       parentReference: { driveId: 'DR' } },
                                                                                     { id: 'I1', name: 'Clientes', folder: { childCount: 2 },
                                                                                       parentReference: { driveId: 'DR' } }
                                                                                   ]))
      get "#{base}/drive/items", headers: auth, as: :json
      expect(response.parsed_body['items'].pluck('name')).to eq(['Clientes', 'b.pdf'])
      expect(response.parsed_body['items'].first).to include('folder' => true, 'drive_id' => 'DR')

      get "/api/v1/accounts/#{account.id}/outsider/apps/summary", headers: auth, as: :json
      expect(response.parsed_body['microsoft']).to include('connected' => true, 'mail' => false, 'calendar' => true)
    end
  end

  it 'gives the Microsoft download address, uploads to a folder and creates a share link' do
    stub_request(:get, "#{graph}/drives/DR/items/I2/content").to_return(status: 302,
                                                                        headers: { 'Location' => 'https://x-my.sharepoint.com/download.aspx?t=1' })
    get "#{base}/drive/items/I2/download", params: { drive_id: 'DR' }, headers: auth
    expect(response.parsed_body['url']).to eq('https://x-my.sharepoint.com/download.aspx?t=1')

    upload = stub_request(:put,
                          %r{#{graph}/drives/DR/items/P1:/foto%20nova.jpg:/content}).to_return(graph_json(id: 'I9', name: 'foto nova.jpg', file: {}))
    file = Rack::Test::UploadedFile.new(StringIO.new('jpg'), 'image/jpeg', original_filename: 'foto nova.jpg')
    post "#{base}/drive/items", params: { drive_id: 'DR', parent_id: 'P1', file: file }, headers: auth
    expect(response).to have_http_status(:created)
    expect(upload).to have_been_requested

    stub_request(:post, "#{graph}/drives/DR/items/I2/createLink").with(body: { type: 'view', scope: 'organization' }.to_json)
                                                                 .to_return(graph_json(link: { webUrl: 'https://x.sharepoint.com/s/1' }))
    post "#{base}/drive/items/I2/share", params: { drive_id: 'DR' }, headers: auth, as: :json
    expect(response.parsed_body['url']).to eq('https://x.sharepoint.com/s/1')
  end

  it 'asks Microsoft for new-mail notices only with version 4 and turns a notice into a live update' do
    subscriptions = Outsider::Teams::Graph::Subscriptions.new(link)
    created = stub_request(:post, "#{graph}/subscriptions").with { |r| JSON.parse(r.body)['resource'].include?("mailFolders('inbox')") }
                                                           .to_return(graph_json(id: 'SUB-M', expirationDateTime: 2.days.from_now.iso8601))
    link.update!(sync_chats: false)
    subscriptions.ensure_mail!
    expect(created).to have_been_requested
    mail_sub = link.subscriptions.find_by(kind: 'mail')
    expect(mail_sub.subscription_id).to eq('SUB-M')

    stub_request(:get, %r{#{graph}/me/messages/NEW1\?}).to_return(graph_json(id: 'NEW1', subject: 'Pedido', isRead: false,
                                                                             from: { emailAddress: { name: 'Cliente', address: 'c@x.com' } }))
    stub_request(:get, %r{#{graph}/me/mailFolders/inbox\?}).to_return(graph_json(unreadItemCount: 7))
    expect(ActionCable.server).to receive(:broadcast).with(agent.pubsub_token, hash_including(event: 'outsider.notice'))
    Outsider::Teams::Graph::ReceiveJob.perform_now(mail_sub.id, 'Users/ms-agent/Messages/NEW1', 'created')
  end
end
