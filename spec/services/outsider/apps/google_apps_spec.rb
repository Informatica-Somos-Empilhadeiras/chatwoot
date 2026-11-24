require 'rails_helper'

RSpec.describe 'Outsider Aplicativos Google (Gmail, Agenda e Drive)', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Agente Um') }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:gmail) { 'https://gmail.googleapis.com/gmail/v1/users/me' }
  let(:drive_api) { 'https://www.googleapis.com/drive/v3' }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/apps/google" }
  let(:all_scopes) { (%w[openid email profile] + Outsider::GoogleLink::FEATURES.values).join(' ') }
  let(:google_app) do
    Outsider::GoogleApp.create!(account_id: account.id, client_id: '123-abc.apps.googleusercontent.com', client_secret: 'segredo')
  end
  let(:link) do
    Outsider::GoogleLink.create!(account: account, user: agent, google_user_id: 'g-1', email: 'agente@gmail.com', display_name: 'Agente Um',
                                 access_token: 'token-g', refresh_token: 'refresh-g', token_expires_at: 1.hour.from_now,
                                 scopes: all_scopes, history_id: '100')
  end

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chat.exemplo.com.br') { example.run }
  end

  before do
    Rails.cache.clear
    google_app
  end

  def ok(body = nil, status: 200, **fields)
    { status: status, body: (body || fields).to_json, headers: json_headers }
  end

  # resposta do lote do Gmail (multipart/mixed, uma parte HTTP por pedido)
  def batch(*items)
    parts = items.each_with_index.map do |item, index|
      "--batch_x\r\nContent-Type: application/http\r\nContent-ID: <response-item#{index}>\r\n\r\n" \
        "HTTP/1.1 #{item ? '200 OK' : '404 Not Found'}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n#{(item || {}).to_json}\r\n"
    end
    { status: 200, body: "#{parts.join}--batch_x--", headers: { 'Content-Type' => 'multipart/mixed; boundary=batch_x' } }
  end

  def b64(text)
    Base64.urlsafe_encode64(text)
  end

  def auth(user = agent)
    user.create_new_auth_token
  end

  describe 'Configurações > Google' do
    it 'saves the company app, signs in a person and finishes on the callback' do
      Outsider::GoogleApp.delete_all
      put "#{base}/account/app", params: { client_id: 'abc', client_secret: 'x' }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      put "#{base}/account/app", params: { client_id: '999-xyz.apps.googleusercontent.com', client_secret: 'segredo' }, headers: auth(admin),
                                 as: :json
      expect(response).to have_http_status(:no_content)
      put "#{base}/account/app", params: { client_id: '999-xyz.apps.googleusercontent.com' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{base}/account/authorize", headers: auth, as: :json
      url = URI.parse(response.parsed_body['url'])
      query = Rack::Utils.parse_query(url.query)
      expect(url.host).to eq('accounts.google.com')
      expect(query).to include('client_id' => '999-xyz.apps.googleusercontent.com', 'access_type' => 'offline',
                               'redirect_uri' => 'https://chat.exemplo.com.br/outsider/google/oauth/callback')
      expect(query['scope'].split).to include('https://www.googleapis.com/auth/gmail.modify', 'https://www.googleapis.com/auth/drive',
                                              'https://www.googleapis.com/auth/calendar.events')

      get '/outsider/google/oauth/callback', params: { code: 'CODE', state: query['state'] }
      expect(response).to redirect_to(%r{/app/accounts/#{account.id}/settings/outsider/google\?google_oauth})

      stub_request(:post, 'https://oauth2.googleapis.com/token').with(body: hash_including('code' => 'CODE'))
                                                                .to_return(ok(access_token: 'novo', refresh_token: 'rt', expires_in: 3599,
                                                                              scope: all_scopes))
      profile = ok(sub: 'g-77', email: 'pessoa@gmail.com', name: 'Pessoa')
      stub_request(:get, 'https://openidconnect.googleapis.com/v1/userinfo').to_return(profile)
      stub_request(:get, "#{gmail}/profile").to_return(ok(historyId: '555'))
      post "#{base}/account/finish", params: { code: 'CODE', state: query['state'] }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('email' => 'pessoa@gmail.com', 'mail' => true, 'drive' => true, 'calendar' => true)
      saved = Outsider::GoogleLink.find_by(user_id: agent.id)
      expect(saved.refresh_token).to eq('rt')
      expect(saved.history_id).to eq('555')
      expect(saved.access_token_encrypted).not_to include('novo')

      # outra pessoa do Chatwoot não pode ligar a mesma conta Google
      other = create(:user, account: account, role: :agent)
      post "#{base}/account/authorize", headers: auth(other), as: :json
      other_state = Rack::Utils.parse_query(URI.parse(response.parsed_body['url']).query)['state']
      post "#{base}/account/finish", params: { code: 'CODE', state: other_state }, headers: auth(other), as: :json
      expect(response.parsed_body['error']).to eq('already_linked')
      # state de outra pessoa não vale
      post "#{base}/account/finish", params: { code: 'CODE', state: query['state'] }, headers: auth(other), as: :json
      expect(response.parsed_body['error']).to eq('state')

      revoke = stub_request(:post, 'https://oauth2.googleapis.com/revoke').to_return(status: 200)
      delete "#{base}/account", headers: auth, as: :json
      expect(revoke).to have_been_requested
      expect(Outsider::GoogleLink.where(user_id: agent.id)).to be_empty
    end

    it 'shows the summary block and asks to sign in again when Google drops the access' do
      link.update!(token_expires_at: 1.minute.ago)
      stub_request(:post, 'https://oauth2.googleapis.com/token').to_return(ok({ error: 'invalid_grant', error_description: 'revoked' },
                                                                              status: 400))
      get "#{base}/mail/folders", headers: auth, as: :json
      expect(response.parsed_body['error']).to eq('reconnect')
      expect(link.reload.status).to eq('reconnect')

      get "/api/v1/accounts/#{account.id}/outsider/apps/summary", headers: auth, as: :json
      expect(response.parsed_body['google']).to include('configured' => true, 'connected' => true, 'status' => 'reconnect')
      get "#{base}/mail/folders", headers: auth, as: :json
      expect(response.parsed_body['error']).to eq('reconnect')
    end
  end

  describe 'Gmail' do
    before { link }

    it 'lists the labels like Outlook folders and the Primary inbox in one batch' do
      stub_request(:get, "#{gmail}/labels").to_return(ok(labels: [
                                                           { id: 'INBOX', type: 'system' }, { id: 'Label_1', name: 'Clientes', type: 'user' },
                                                           { id: 'Label_2', name: 'Oculto', type: 'user', labelListVisibility: 'labelHide' }
                                                         ]))
      stub_request(:post, 'https://gmail.googleapis.com/batch/gmail/v1')
        .to_return(batch({ id: 'DRAFT', messagesTotal: 2 }, { id: 'SENT', messagesTotal: 9 }, { id: 'SPAM', messagesUnread: 1 },
                         { id: 'TRASH' }, { id: 'CATEGORY_PROMOTIONS', messagesTotal: 30 }, { id: 'CATEGORY_SOCIAL', messagesTotal: 0 },
                         nil, nil, { id: 'Label_1', messagesUnread: 3, messagesTotal: 5 }))
      unread = stub_request(:get, %r{#{gmail}/messages\?}).with(query: hash_including('maxResults' => '100'))
                                                          .to_return(ok(messages: [{ id: 'a' }, { id: 'b' }]))
      get "#{base}/mail/folders", headers: auth, as: :json
      folders = response.parsed_body['payload']
      expect(folders.pluck('kind')).to eq(%w[inbox promotions drafts sentitems archive junkemail deleteditems label])
      expect(folders.first).to include('id' => 'INBOX', 'name' => 'Principal', 'unread' => 2)
      expect(folders.find { |item| item['kind'] == 'sentitems' }['movable']).to be(false)
      expect(folders.last).to include('name' => 'Clientes', 'unread' => 3)
      expect(unread).to have_been_requested

      list = stub_request(:get, %r{#{gmail}/messages\?}).with(query: hash_including('labelIds' => 'INBOX', 'maxResults' => '25'))
                                                        .to_return(ok(messages: [{ id: 'M1' }, { id: 'M2' }], nextPageToken: 'P2'))
      headers = [{ name: 'From', value: '=?UTF-8?Q?Jo=C3=A3o?= <joao@cliente.com>' }, { name: 'Subject', value: 'Orçamento' }]
      first = { id: 'M1', labelIds: %w[INBOX UNREAD STARRED], snippet: 'Bom dia &amp; obrigado', internalDate: '1795000000000',
                payload: { mimeType: 'multipart/mixed', headers: headers } }
      stub_request(:post, 'https://gmail.googleapis.com/batch/gmail/v1').with(body: /format=metadata/).to_return(batch(first, nil))
      get "#{base}/mail/messages", params: { folder: 'inbox', filter: 'unread' }, headers: auth
      expect(list).to have_been_requested
      query = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map(&:uri).reverse
                                      .find { |uri| uri.path.end_with?('/messages') }.query_values
      expect(query['q']).to include('-category:promotions', 'is:unread')
      body = response.parsed_body
      expect(body['items'].size).to eq(1)
      expect(body['items'].first).to include('id' => 'M1', 'subject' => 'Orçamento', 'unread' => true, 'flagged' => true,
                                             'has_attachments' => true, 'preview' => 'Bom dia & obrigado',
                                             'from' => { 'name' => 'João', 'email' => 'joao@cliente.com' })

      more = stub_request(:get, %r{#{gmail}/messages\?}).with(query: hash_including('pageToken' => 'P2', 'labelIds' => 'INBOX'))
                                                        .to_return(ok(messages: []))
      get "#{base}/mail/messages", params: { cursor: body['next'] }, headers: auth
      expect(more).to have_been_requested
      get "#{base}/mail/messages", params: { cursor: 'lixo!' }, headers: auth
      expect(response.parsed_body['error']).to eq('invalid')
    end

    it 'opens a message in Latin-1, marks it read, links inline images and serves the attachment' do
      create(:contact, account: account, email: 'joao@cliente.com', name: 'João Cliente')
      html = '<html><body><p onclick="x()">Olá</p><script>alert(1)</script><img src="cid:logo@x"></body></html>'.encode('ISO-8859-1')
      html_part = { partId: '0.0', mimeType: 'text/html', headers: [{ name: 'Content-Type', value: 'text/html; charset=ISO-8859-1' }],
                    body: { size: 10, data: Base64.urlsafe_encode64(html.b) } }
      logo = { partId: '0.1', mimeType: 'image/png', filename: 'logo.png', headers: [{ name: 'Content-ID', value: '<logo@x>' }],
               body: { size: 5, attachmentId: 'ATT-LOGO' } }
      pdf = { partId: '1', mimeType: 'application/pdf', filename: 'proposta.pdf',
              headers: [{ name: 'Content-Disposition', value: 'attachment; filename="proposta.pdf"' }],
              body: { size: 9, attachmentId: 'ATT-PDF' } }
      headers = [{ name: 'From', value: 'João <joao@cliente.com>' }, { name: 'To', value: 'agente@gmail.com, Outro <outro@x.com>' },
                 { name: 'Subject', value: 'Orçamento' }]
      payload = { mimeType: 'multipart/mixed', headers: headers,
                  parts: [{ partId: '0', mimeType: 'multipart/related', parts: [html_part, logo] }, pdf] }
      stub_request(:get, "#{gmail}/messages/M1?format=full")
        .to_return(ok(id: 'M1', threadId: 'T1', labelIds: %w[INBOX UNREAD], snippet: 'Olá', internalDate: '1795000000000', payload: payload))
      read = stub_request(:post, "#{gmail}/messages/M1/modify").with(body: { removeLabelIds: ['UNREAD'] }.to_json)
                                                               .to_return(ok(id: 'M1'))
      get "#{base}/mail/messages/M1", headers: auth
      expect(read).to have_been_requested
      body = response.parsed_body
      expect(body['unread']).to be(false)
      expect(body['html']).to include('Olá').and include('/outsider/apps/file?t=')
      expect(body['html']).not_to include('<script')
      expect(body['html']).not_to include('onclick')
      expect(body['attachments'].pluck('name')).to eq(['proposta.pdf'])
      expect(body['to'].pluck('email')).to eq(%w[agente@gmail.com outro@x.com])
      expect(body['chatwoot']).to be_present

      stub_request(:get, "#{gmail}/messages/M1/attachments/ATT-PDF").to_return(ok(data: b64('%PDF-1.4')))
      get body['attachments'].first['url']
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('%PDF-1.4')
      expect(response.headers['Content-Type']).to eq('application/pdf')

      link.update!(status: 'reconnect')
      get body['attachments'].first['url']
      expect(response.body).to include('Configurações &gt; Google')
    end

    it 'replies in the same thread with the quote and Bcc, and moves to the trash or a label' do
      stub_request(:get, "#{gmail}/messages/M1?format=full").to_return(ok(
                                                                         id: 'M1', threadId: 'T1', labelIds: %w[INBOX],
                                                                         payload: { mimeType: 'text/plain', headers: [
                                                                           { name: 'From', value: 'João <joao@cliente.com>' },
                                                                           { name: 'To', value: 'agente@gmail.com, outro@x.com' },
                                                                           { name: 'Cc', value: 'chefe@x.com' },
                                                                           { name: 'Subject', value: 'Orçamento' },
                                                                           { name: 'Message-ID', value: '<orig@mail.gmail.com>' }
                                                                         ], body: { data: b64('texto original') } }
                                                                       ))
      sent = stub_request(:post, 'https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send?uploadType=multipart')
             .to_return(ok(id: 'S1'))
      post "#{base}/mail/messages", params: { mode: 'reply_all', source_id: 'M1', text: 'Segue o valor', subject: 'Re: Orçamento',
                                              bcc: ['oculto@x.com'], files: [fixture_file_upload('sample.pdf', 'application/pdf')] },
                                    headers: auth
      expect(response).to have_http_status(:created)
      expect(sent).to have_been_requested
      raw = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find { |r| r.uri.path.end_with?('/messages/send') }.body
      expect(raw).to include('"threadId":"T1"', 'In-Reply-To: <orig@mail.gmail.com>', 'Bcc: oculto@x.com', 'multipart/alternative',
                             'filename=sample.pdf')
      expect(raw).to match(/^To: joao@cliente.com,\s*outro@x.com/)
      expect(raw).to match(/^Cc: chefe@x.com/)
      expect(raw).not_to match(/^(To|Cc):.*agente@gmail.com/)

      post "#{base}/mail/messages", params: { mode: 'new', text: 'oi' }, headers: auth, as: :json
      expect(response.parsed_body['error']).to eq('no_recipient')

      trash = stub_request(:post, "#{gmail}/messages/M1/trash").to_return(ok(id: 'M1'))
      post "#{base}/mail/messages/M1/move", params: { destination: 'deleteditems' }, headers: auth, as: :json
      expect(trash).to have_been_requested
      stub_request(:get, "#{gmail}/messages/M1?fields=labelIds&format=minimal").to_return(ok(labelIds: ['INBOX']))
      label = stub_request(:post, "#{gmail}/messages/M1/modify").with(body: { addLabelIds: ['Label_1'], removeLabelIds: ['INBOX'] }.to_json)
                                                                .to_return(ok(id: 'M1'))
      post "#{base}/mail/messages/M1/move", params: { destination: 'Label_1' }, headers: auth, as: :json
      expect(label).to have_been_requested
      post "#{base}/mail/messages/M1/move", params: { destination: 'sentitems' }, headers: auth, as: :json
      expect(response.parsed_body['error']).to eq('invalid')
    end

    it 'asks for the missing permission when the person unchecked Gmail' do
      link.update!(scopes: 'openid email https://www.googleapis.com/auth/drive')
      get "#{base}/mail/folders", headers: auth, as: :json
      expect(response.parsed_body['error']).to eq('scope_outdated')
    end
  end

  describe 'observador do Gmail' do
    before { link }

    it 'pushes only new Primary mail, starts over when the history is too old and skips recent checks' do
      added = [%w[N1 INBOX UNREAD CATEGORY_PERSONAL], %w[N2 INBOX UNREAD CATEGORY_PROMOTIONS], %w[N3 SENT INBOX]].map do |id, *labels|
        { messagesAdded: [{ message: { id: id, labelIds: labels } }] }
      end
      stub_request(:get, %r{#{gmail}/history\?}).to_return(ok(historyId: '130', history: added))
      stub_request(:get, %r{#{gmail}/messages\?}).to_return(ok(messages: [{ id: 'N1' }]))
      headers = [{ name: 'From', value: 'Cliente <c@x.com>' }, { name: 'Subject', value: 'Peça' }]
      fresh = { id: 'N1', labelIds: %w[INBOX UNREAD], snippet: 'Preciso de uma peça', internalDate: '1795000000000',
                payload: { headers: headers } }
      stub_request(:post, 'https://gmail.googleapis.com/batch/gmail/v1').to_return(batch(fresh))
      expect(Outsider::Apps::MailPush).to receive(:new).with(agent, account, provider: 'google', item: hash_including(id: 'N1')).once
                                                       .and_call_original
      allow(ActionCable.server).to receive(:broadcast)
      Outsider::Apps::Google::WatchJob.perform_now
      expect(ActionCable.server).to have_received(:broadcast)
        .with(agent.pubsub_token, hash_including(data: hash_including(provider: 'google', action: 'created', unread: 1)))
      expect(link.reload.history_id).to eq('130')

      # rodou agora: a próxima rodada pula
      Outsider::Apps::Google::WatchJob.perform_now
      expect(a_request(:get, %r{#{gmail}/history\?})).to have_been_made.once

      link.update_columns(checked_at: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      stub_request(:get, %r{#{gmail}/history\?}).to_return(ok({ error: { code: 404, message: 'Requested entity was not found.' } },
                                                              status: 404))
      stub_request(:get, "#{gmail}/profile").to_return(ok(historyId: '900'))
      Outsider::Apps::Google::WatchJob.perform_now
      expect(link.reload.history_id).to eq('900')
    end
  end

  describe 'Drive' do
    before { link }

    it 'lists My Drive, previews a Google Doc as PDF, downloads it as Word and streams the file' do
      folder_type = Outsider::Apps::Google::Drive::FOLDER
      files = [
        { id: 'D1', name: 'Relatório', mimeType: 'application/vnd.google-apps.document', modifiedTime: '2026-11-20T10:00:00Z',
          webViewLink: 'https://docs.google.com/document/d/D1' },
        { id: 'F1', name: 'Pasta', mimeType: folder_type },
        { id: 'S1', name: 'Atalho', mimeType: Outsider::Apps::Google::Drive::SHORTCUT,
          shortcutDetails: { targetId: 'F9', targetMimeType: folder_type } }
      ]
      list = stub_request(:get, %r{#{drive_api}/files\?}).with(query: hash_including('q' => "'root' in parents and trashed = false"))
                                                         .to_return(ok(files: files, nextPageToken: 'NP'))
      get "#{base}/drive/items", headers: auth
      expect(list).to have_been_requested
      items = response.parsed_body['items']
      expect(items.map { |item| [item['id'], item['folder']] }).to eq([['D1', false], ['F1', true], ['F9', true]])
      expect(items.first['size']).to be_nil

      stub_request(:get, %r{#{drive_api}/files/D1\?}).to_return(ok(id: 'D1', name: 'Relatório', mimeType: 'application/vnd.google-apps.document',
                                                                   webViewLink: 'https://docs.google.com/document/d/D1'))
      get "#{base}/drive/items/D1/preview", headers: auth
      preview = response.parsed_body
      expect(preview['kind']).to eq('pdf')
      expect(preview['edit_url']).to eq('https://docs.google.com/document/d/D1')

      export = stub_request(:get, "#{drive_api}/files/D1/export?mimeType=application/pdf").to_return(status: 200, body: '%PDF-doc')
      get preview['view_url']
      expect(export).to have_been_requested
      expect(response.body).to eq('%PDF-doc')
      expect(response.headers['Content-Disposition']).to include('inline').and include('Relat')

      get "#{base}/drive/items/D1/download", headers: auth
      word = stub_request(:get, %r{#{drive_api}/files/D1/export\?mimeType=application/vnd.openxmlformats}).to_return(status: 200, body: 'DOCX')
      get response.parsed_body['url']
      expect(word).to have_been_requested
      expect(response.headers['Content-Disposition']).to include('attachment').and include('.docx')
    end

    it 'uploads in a resumable session, creates folders, shares and moves to the trash' do
      start = stub_request(:post, %r{https://www.googleapis.com/upload/drive/v3/files\?.*uploadType=resumable})
              .with(body: hash_including('name' => 'sample.pdf', 'parents' => ['PASTA']))
              .to_return(status: 200, headers: { 'Location' => 'https://www.googleapis.com/upload/drive/v3/files?upload_id=U1' })
      chunk = stub_request(:put, 'https://www.googleapis.com/upload/drive/v3/files?upload_id=U1')
              .to_return(ok(id: 'NEW', name: 'sample.pdf', mimeType: 'application/pdf', size: '100'))
      post "#{base}/drive/items", params: { parent_id: 'PASTA', file: fixture_file_upload('sample.pdf', 'application/pdf') }, headers: auth
      expect(response).to have_http_status(:created)
      expect([start, chunk]).to all(have_been_requested)
      expect(response.parsed_body).to include('id' => 'NEW', 'size' => 100)

      new_folder = ok(id: 'NF', name: 'Clientes', mimeType: Outsider::Apps::Google::Drive::FOLDER)
      folder = stub_request(:post, %r{#{drive_api}/files\?}).with(body: hash_including('name' => 'Clientes', 'parents' => ['root']))
                                                            .to_return(new_folder)
      post "#{base}/drive/folders", params: { name: 'Clientes' }, headers: auth, as: :json
      expect(folder).to have_been_requested
      expect(response.parsed_body['folder']).to be(true)

      stub_request(:get, %r{#{drive_api}/files/NEW\?}).to_return(ok(id: 'NEW', name: 'sample.pdf', webViewLink: 'https://drive.google.com/file/d/NEW/view'))
      anyone = stub_request(:post, %r{#{drive_api}/files/NEW/permissions}).with(body: { role: 'reader', type: 'anyone' }.to_json)
                                                                          .to_return(ok(id: 'anyone'))
      post "#{base}/drive/items/NEW/share", params: { scope: 'organization' }, headers: auth, as: :json
      expect(anyone).not_to have_been_requested
      post "#{base}/drive/items/NEW/share", params: { scope: 'anonymous' }, headers: auth, as: :json
      expect(anyone).to have_been_requested
      expect(response.parsed_body['url']).to eq('https://drive.google.com/file/d/NEW/view')

      trash = stub_request(:patch, %r{#{drive_api}/files/NEW\?}).with(body: { trashed: true }.to_json).to_return(ok(id: 'NEW'))
      delete "#{base}/drive/items/NEW", headers: auth, as: :json
      expect(trash).to have_been_requested
    end
  end

  describe 'Agenda' do
    before { link }

    it 'lists events in the person time zone and books a Google Meet with the invitees' do
      stub_request(:get, %r{https://www.googleapis.com/calendar/v3/calendars/primary/events\?})
        .with(query: hash_including('singleEvents' => 'true', 'timeZone' => 'America/Sao_Paulo'))
        .to_return(ok(items: [
                        { id: 'E1', summary: 'Visita', start: { dateTime: '2026-11-24T13:00:00Z' }, end: { dateTime: '2026-11-24T14:00:00Z' },
                          hangoutLink: 'https://meet.google.com/abc', organizer: { email: 'agente@gmail.com', self: true },
                          attendees: [{ email: 'c@x.com', responseStatus: 'accepted' }], description: '<b>Levar</b> catálogo' },
                        { id: 'E2', summary: 'Feriado', start: { date: '2026-11-25' }, end: { date: '2026-11-26' },
                          organizer: { email: 'outro@x.com' }, attendees: [{ email: 'agente@gmail.com', self: true, responseStatus: 'tentative' }] },
                        { id: 'E3', status: 'cancelled', start: { date: '2026-11-27' }, end: { date: '2026-11-28' } }
                      ]))
      get "#{base}/calendar/events", params: { from: '2026-11-23T03:00:00Z', to: '2026-11-30T03:00:00Z', time_zone: 'America/Sao_Paulo' },
                                     headers: auth
      events = response.parsed_body['payload']
      expect(events.size).to eq(2)
      expect(events.first).to include('start' => '2026-11-24T10:00:00', 'end' => '2026-11-24T11:00:00', 'online' => true,
                                      'join_url' => 'https://meet.google.com/abc', 'mine' => true, 'response' => 'organizer',
                                      'preview' => 'Levar catálogo')
      expect(events.last).to include('all_day' => true, 'start' => '2026-11-25T00:00:00', 'response' => 'tentativelyAccepted')

      created = stub_request(:post, %r{calendars/primary/events\?.*conferenceDataVersion=1})
                .with(query: hash_including('sendUpdates' => 'all'),
                      body: hash_including('summary' => 'Reunião', 'attendees' => [{ 'email' => 'c@x.com' }],
                                           'start' => { 'dateTime' => '2026-11-26T09:00:00', 'timeZone' => 'America/Sao_Paulo' }))
                .to_return(ok(id: 'NEW', summary: 'Reunião', start: { dateTime: '2026-11-26T09:00:00-03:00' },
                              end: { dateTime: '2026-11-26T10:00:00-03:00' }, hangoutLink: 'https://meet.google.com/new'))
      post "#{base}/calendar/events", params: { subject: 'Reunião', start: '2026-11-26T09:00:00', end: '2026-11-26T10:00:00',
                                                time_zone: 'America/Sao_Paulo', online: true, attendees: ['c@x.com'] }, headers: auth, as: :json
      expect(created).to have_been_requested
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find { |r| r.method == :post && r.uri.path.end_with?('/events') }
                                                                                .body).to include('hangoutsMeet')
      expect(response.parsed_body).to include('id' => 'NEW', 'start' => '2026-11-26T09:00:00')

      create(:user, account: account, role: :agent, name: 'Colega', email: 'colega@empresa.com')
      get "#{base}/calendar/people", headers: auth, as: :json
      expect(response.parsed_body['payload']).to include({ 'name' => 'Colega', 'email' => 'colega@empresa.com' })
    end
  end
end
