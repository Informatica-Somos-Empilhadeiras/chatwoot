require 'rails_helper'

RSpec.describe 'Outsider visualizador de documentos', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chat.exemplo.com.br') { example.run }
  end

  def attach(name, content_type, body = nil)
    attachment = message.attachments.new(account_id: account.id, file_type: :file)
    io = body ? StringIO.new(body) : Rails.root.join('spec/assets/sample.pdf').open
    attachment.file.attach(io: io, filename: name, content_type: content_type)
    attachment.save!
    attachment
  end

  def view(attachment, user = agent)
    get "/api/v1/accounts/#{account.id}/outsider/file_views/#{attachment.id}", headers: user.create_new_auth_token, as: :json
  end

  it 'opens a PDF inside Chatwoot through a short-lived signed address' do
    pdf = attach('Proposta Transportadora.pdf', 'application/pdf')
    view(pdf)
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('kind' => 'pdf', 'reason' => nil, 'name' => 'Proposta Transportadora.pdf', 'extension' => 'pdf')
    expect(body['view_url']).to start_with('/outsider/arquivo/').and end_with('/proposta-transportadora.pdf')

    get body['view_url']
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    expect(response.headers['Content-Disposition']).to start_with('inline')
    expect(response.body.bytesize).to eq(pdf.file.byte_size)
  end

  it 'refuses tampered or expired addresses and people who cannot see the conversation' do
    pdf = attach('Proposta.pdf', 'application/pdf')
    view(pdf)
    body = response.parsed_body

    get '/outsider/arquivo/token-mexido/x.pdf'
    expect(response).to have_http_status(:not_found)

    travel 16.minutes do
      get body['view_url']
      expect(response).to have_http_status(:not_found)
    end

    view(pdf, outsider_agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'sends Word, Excel and PowerPoint to the Office web viewer only when Chatwoot is public, and shows text as text' do
    docx = attach('Contrato.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'PK fake')
    view(docx)
    expect(response.parsed_body).to include('kind' => 'office')
    expect(response.parsed_body['view_url']).to start_with('https://view.officeapps.live.com/op/embed.aspx?src=https%3A%2F%2Fchat.exemplo.com.br%2Foutsider%2Farquivo%2F')

    ClimateControl.modify(FRONTEND_URL: 'http://localhost:3000') do
      view(docx)
      expect(response.parsed_body).to include('kind' => 'none', 'reason' => 'not_public', 'view_url' => nil)
    end

    csv = attach('frota.csv', 'text/csv', "placa;modelo\nABC;2,5t\n")
    view(csv)
    get response.parsed_body['view_url']
    expect(response.media_type).to eq('text/plain')
    expect(response.body).to include('ABC;2,5t')

    zip = attach('fotos.zip', 'application/zip', 'zip')
    view(zip)
    expect(response.parsed_body).to include('kind' => 'none', 'reason' => 'unsupported')

    big = attach('Frota.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'x')
    big.file.blob.update!(byte_size: 6.megabytes)
    view(big)
    expect(response.parsed_body).to include('kind' => 'none', 'reason' => 'too_big')
  end
end
