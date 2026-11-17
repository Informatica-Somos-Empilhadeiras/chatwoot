require 'rails_helper'
require 'open3'

RSpec.describe 'Outsider área Teams: baixar, zip e encaminhar', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:link) do
    Outsider::TeamsLink.create!(account: account, user: agent, ms_user_id: 'ms-agent', display_name: 'Agente Teams',
                                access_token: 'token-agente', refresh_token: 'refresh-agente', token_expires_at: 1.hour.from_now)
  end
  let(:thread) { link.threads.create!(kind: 'chat', chat_id: '19:chat', chat_type: 'group', title: 'Obra Goiânia') }
  let(:target) { link.threads.create!(kind: 'chat', chat_id: '19:outro', chat_type: 'oneOnOne', title: 'Ricardo') }
  let(:files) { Outsider::Teams::Graph::Files }
  let(:hosted) { 'https://graph.microsoft.com/v1.0/chats/19:chat/messages/1/hostedContents/aa/$value' }
  let(:message) do
    thread.messages.create!(graph_id: '111', sender_name: 'Ana Paula', sent_at: 1.minute.ago, attachments: [
                              { 'kind' => 'video', 'name' => 'descarga.mp4', 'size' => 9, 'drive_id' => 'drive-1', 'item_id' => 'item-1',
                                'web_url' => 'https://empresa.sharepoint.com/:v:/r/descarga' },
                              { 'kind' => 'image', 'name' => 'imagem-1.png', 'hosted' => hosted },
                              { 'kind' => 'file', 'name' => 'apagado.pdf', 'drive_id' => 'drive-1', 'item_id' => 'item-2' }
                            ])
  end

  def stub_file(item, body, url: "https://empresa.sharepoint.com/download.aspx?id=#{item}")
    stub_request(:get, "https://graph.microsoft.com/v1.0/drives/drive-1/items/#{item}/content")
      .to_return(status: 302, headers: { 'Location' => url })
    stub_request(:get, url).to_return(status: 200, body: body, headers: { 'Content-Type' => 'video/mp4' })
  end

  def unzip(bytes)
    path = Rails.root.join('tmp', "teams-#{SecureRandom.hex(4)}.zip")
    File.binwrite(path, bytes)
    script = 'import sys,json,zipfile;z=zipfile.ZipFile(sys.argv[1]);assert z.testzip() is None;' \
             'print(json.dumps({n: z.read(n).decode("utf-8","replace") for n in z.namelist()}))'
    out, status = Open3.capture2('python3', '-c', script, path.to_s)
    expect(status).to be_success
    JSON.parse(out)
  ensure
    FileUtils.rm_f(path)
  end

  it 'baixa o arquivo pelo Chatwoot com o nome certo e explica quando a Microsoft não deixa' do
    stub_file('item-1', 'mp4-bytes')
    get files.media_url(message, 0, 'download')
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('mp4-bytes')
    expect(response.headers['Content-Disposition']).to include('attachment', 'descarga.mp4')

    # endereço antigo (Baixar de antes desta versão) vai para o novo
    old = files.media_url(message, 0, 'download').sub(files::DOWNLOAD_PATH, files::MEDIA_PATH)
    get old
    expect(response).to redirect_to(%r{/outsider/teams/download\?t=})

    stub_request(:get, 'https://graph.microsoft.com/v1.0/drives/drive-1/items/item-2/content')
      .to_return(status: 403, body: { error: { code: 'accessDenied', message: 'blocked' } }.to_json, headers: json_headers)
    get files.media_url(message, 2, 'download')
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('A Microsoft não deixou baixar')

    get "#{files.media_url(message, 0, 'download')}x"
    expect(response.body).to include('expirou')

    # sem /content, ainda tenta o @microsoft.graph.downloadUrl
    stub_request(:get, 'https://graph.microsoft.com/v1.0/drives/drive-1/items/item-1/content').to_return(status: 200, body: '')
    stub_request(:get, %r{graph.microsoft.com/v1.0/drives/drive-1/items/item-1\?})
      .to_return(status: 200, body: { '@microsoft.graph.downloadUrl' => 'https://empresa.sharepoint.com/dl2' }.to_json, headers: json_headers)
    stub_request(:get, 'https://empresa.sharepoint.com/dl2').to_return(status: 200, body: 'mp4-de-novo')
    get files.media_url(message, 0, 'download')
    expect(response.body).to eq('mp4-de-novo')
  end

  it 'monta um zip com os arquivos escolhidos e lista o que não deu para baixar' do
    stub_file('item-1', 'mp4-bytes')
    stub_request(:get, hosted).to_return(status: 200, body: 'png-bytes', headers: { 'Content-Type' => 'image/png' })
    stub_request(:get, 'https://graph.microsoft.com/v1.0/drives/drive-1/items/item-2/content').to_return(status: 404, body: '')

    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/zip",
         params: { items: [0, 1, 2, 9].map { |index| { message_id: message.id, index: index } } },
         headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['count']).to eq(3)
    get response.parsed_body['url']
    expect(response.headers['Content-Type']).to eq('application/zip')
    expect(response.headers['Content-Disposition']).to include('Teams - Obra Goi')
    entries = unzip(response.body)
    expect(entries).to include('descarga.mp4' => 'mp4-bytes', 'imagem-1.png' => 'png-bytes')
    expect(entries['nao-baixados.txt']).to include('Arquivos que não entraram no zip')
    expect(entries.keys.size).to eq(3)

    # a área dos outros continua fechada
    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/zip",
         params: { items: [{ message_id: message.id, index: 0 }] }, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'encaminha copiando os arquivos para o destino' do
    sent_image = 'https://graph.microsoft.com/v1.0/chats/19:outro/messages/999/hostedContents/bb/$value'
    message.update!(content: 'Fotos da descarga', attachments: message.attachments.first(2))
    post "/api/v1/accounts/#{account.id}/outsider/teams_threads/#{thread.id}/forward",
         params: { message_ids: [message.id], target_ids: [target.id] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    forwarded = target.messages.sole
    expect(forwarded).to have_attributes(status: 'sending', mine: true)
    expect(forwarded.content).to eq("↪ Encaminhada de Ana Paula\nFotos da descarga")
    expect(forwarded.attachments.map { |item| item['forward_from'] }).to eq([{ 'm' => message.id, 'i' => 0 }, { 'm' => message.id, 'i' => 1 }])

    stub_file('item-1', 'mp4-bytes')
    stub_request(:get, hosted).to_return(status: 200, body: 'png-bytes', headers: { 'Content-Type' => 'image/png' })
    upload = stub_request(:put, %r{graph.microsoft.com/v1.0/me/drive/root:/Microsoft%20Teams%20Chat%20Files/descarga.mp4:/content})
             .with(body: 'mp4-bytes')
             .to_return(status: 201, headers: json_headers,
                        body: { id: 'novo-1', name: 'descarga.mp4', size: 9, eTag: '"{11111111-2222-3333-4444-555555555555},1"',
                                webUrl: 'https://empresa-my.sharepoint.com/personal/a/descarga.mp4', file: { mimeType: 'video/mp4' },
                                parentReference: { driveId: 'drive-me' } }.to_json)
    sent = stub_request(:post, 'https://graph.microsoft.com/v1.0/chats/19:outro/messages')
           .with do |request|
      JSON.parse(request.body).then do |body|
        body['attachments'].sole['name'] == 'descarga.mp4' && body['hostedContents'].size == 1
      end
    end
           .to_return(status: 201, headers: json_headers,
                      body: { id: '999', createdDateTime: Time.current.iso8601, body: { content: %(<img src="#{sent_image}">) } }.to_json)

    Outsider::Teams::Graph::ForwardJob.perform_now([forwarded.id])
    expect(upload).to have_been_requested
    expect(sent).to have_been_requested
    expect(forwarded.reload).to have_attributes(status: 'sent', graph_id: '999')
    expect(forwarded.attachments.map { |item| item['name'] }).to eq(['descarga.mp4', 'imagem-1.png'])
    expect(forwarded.attachments.last['hosted']).to include('hostedContents/bb')
  end

  it 'escreve um zip que os programas abrem, com nomes repetidos e acentos' do
    out = +''
    zip = Outsider::ZipStream.new(->(bytes) { out << bytes })
    zip.add('relatório.txt') { |write| write.call('um') }
    zip.add('relatório.txt') { |write| write.call('dois') }
    zip.add('a/b:c.txt') { |write| write.call('') }
    zip.finish
    expect(unzip(out)).to eq('relatório.txt' => 'um', 'relatório (2).txt' => 'dois', 'a_b_c.txt' => '')
  end
end
