require 'rails_helper'

RSpec.describe 'Outsider miniatura dos documentos', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  # zip mínimo (como um .docx/.xlsx/.pptx): entradas comprimidas com deflate, sem gem
  def build_zip(files)
    body = ''.b
    directory = ''.b
    files.each do |name, content|
      local, central = zip_headers(name, content.b, body.bytesize)
      body << local
      directory << central
    end
    body + directory + [0x06054b50, 0, 0, files.size, files.size, directory.bytesize, body.bytesize, 0].pack('VvvvvVVv')
  end

  def zip_headers(name, data, offset)
    packed = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)
    sizes = [Zlib.crc32(data), packed.bytesize, data.bytesize, name.bytesize]
    local = [0x04034b50, 20, 0, 8, 0, 0, *sizes, 0].pack('VvvvvvVVVvv') + name.b + packed
    central = [0x02014b50, 20, 20, 0, 8, 0, 0, *sizes, 0, 0, 0, 0, 0, offset].pack('VvvvvvvVVVvvvvvVV') + name.b
    [local, central]
  end

  def peek(name, content_type, body)
    attachment = message.attachments.new(account_id: account.id, file_type: :file)
    attachment.file.attach(io: StringIO.new(body), filename: name, content_type: content_type)
    attachment.save!
    get "/api/v1/accounts/#{account.id}/outsider/file_views/#{attachment.id}/peek", headers: agent.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'shows the beginning of Word and Excel files and the thumbnail Office keeps inside the file' do
    w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
    document = "<w:document #{w}><w:body>" \
               '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Proposta Comercial</w:t></w:r></w:p>' \
               '<w:p><w:r><w:t xml:space="preserve">Cliente: </w:t></w:r><w:r><w:t>Transportadora</w:t></w:r></w:p>' \
               '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Modelo</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Valor</w:t></w:r></w:p></w:tc></w:tr></w:tbl>' \
               '</w:body></w:document>'
    docx = build_zip('word/document.xml' => document, 'docProps/app.xml' => '<Properties><Pages>3</Pages></Properties>')
    expect(peek('Proposta.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', docx)).to eq(
      'type' => 'text', 'pages' => 3,
      'lines' => [{ 't' => 'Proposta Comercial', 'h' => true }, { 't' => 'Cliente: Transportadora', 'h' => false },
                  { 'r' => %w[Modelo Valor] }]
    )

    workbook = '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' \
               '<sheet name="Frota" sheetId="1" r:id="rId1"/></sheets></workbook>'
    rels = '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'
    sheet = '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>' \
            '<row r="2"><c r="A2" t="inlineStr"><is><t>Toyota &amp; Cia</t></is></c><c r="B2"><v>12450</v></c><c r="C2"><v>3.5</v></c></row>' \
            '</sheetData></worksheet>'
    xlsx = build_zip('xl/workbook.xml' => workbook, 'xl/_rels/workbook.xml.rels' => rels, 'xl/worksheets/sheet1.xml' => sheet,
                     'xl/sharedStrings.xml' => '<sst><si><t>Modelo</t></si><si><r><t>Horí</t></r><r><t>metro</t></r></si></sst>')
    expect(peek('Frota.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', xlsx)).to eq(
      'type' => 'table', 'sheet' => 'Frota', 'rows' => [['Modelo', '', 'Horímetro'], ['Toyota & Cia', '12450', '3,50']]
    )

    pptx = build_zip('ppt/slides/slide1.xml' => '<p:sld/>', 'ppt/slides/slide2.xml' => '<p:sld/>', 'docProps/thumbnail.jpeg' => "\xFF\xD8\xFFfoto")
    result = peek('Linha.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', pptx)
    expect(result).to include('type' => 'image', 'pages' => 2)
    expect(result['src']).to eq("data:image/jpeg;base64,#{Base64.strict_encode64("\xFF\xD8\xFFfoto".b)}")
  end

  it 'gives the PDF address for the browser to draw the first page, and nothing for other files' do
    pdf = peek('Proposta.pdf', 'application/pdf', File.binread(Rails.root.join('spec/assets/sample.pdf')))
    expect(pdf['type']).to eq('pdf')
    expect(pdf['url']).to start_with('/outsider/arquivo/')
    expect(peek('lista.csv', 'text/csv', "Nome;Cidade\nAna;São Paulo\n")).to eq('type' => 'table', 'rows' => [%w[Nome Cidade], ['Ana', 'São Paulo']])
    expect(peek('fotos.zip', 'application/zip', build_zip('a.txt' => 'x'))).to eq('type' => 'none')
    expect(peek('quebrado.docx', 'application/octet-stream', 'não é zip')).to eq('type' => 'none')
  end
end
