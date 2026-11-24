require 'rails_helper'

# OUTSIDER: aba "Modelos de relatório" (só administradores) e o relatório da OS / PDF do orçamento saindo no modelo
# escolhido. Sem escolha, sai o relatório original, sem nenhuma leitura a mais no ERP.
RSpec.describe 'Outsider ERP print templates', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/erp" }
  let(:jpeg) { File.binread(Rails.public_path.join('outsider/erp-prints/amostra-1.jpg')) }

  before do
    settings.update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc123')
    stub_request(:get, %r{/KanbanOrdemServico/api/ListaTipoAtendimento}).to_return(
      status: 200, body: [{ 'TipoAtendimento' => 'MANUT. CORRETIVA' }, { 'TipoAtendimento' => 'PREVENTIVA' }].to_json
    )
  end

  def call(verb, path, user: admin, **params)
    send(verb, "#{base}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
  end

  def templates = Outsider::Erp::PrintTemplate.where(account: account)

  it 'is only for administrators' do
    call(:get, 'print_templates', user: agent)
    expect(response).to have_http_status(:forbidden)
  end

  it 'lists the ready templates, the attendance types and the catalog' do
    call(:get, 'print_templates')
    body = response.parsed_body
    expect(body['templates'].pluck('builtin')).to include('os_fotos', 'os_respostas', 'quote_padrao')
    expect(body['attendance_types']).to eq(['MANUT. CORRETIVA', 'PREVENTIVA'])
    expect(body['bindings']).to eq('os' => { 'default' => 'original', 'types' => {} }, 'quote' => { 'default' => 'original' })
    expect(body['catalog']['os']['blocks'].pluck('type')).to include('checklist')
    expect(body['catalog']['quote']['blocks'].pluck('type')).to include('totals')
  end

  it 'saves the studio content cleaned, copies a template and previews it unsaved' do
    call(:get, 'print_templates')
    source = templates.find_by(builtin: 'os_fotos')

    call(:patch, "print_templates/#{source.id}", name: 'OS corretiva', content: { 'blocks' => [{ 'type' => 'checklist', 'photos' => 'without' },
                                                                                               { 'type' => 'nope' }] })
    expect(response.parsed_body['template']).to include('name' => 'OS corretiva', 'block_types' => ['checklist'], 'photos' => false)

    call(:post, 'print_templates', source_id: source.id)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['template']['name']).to eq('OS corretiva (cópia)')

    call(:post, "print_templates/#{source.id}/preview", content: { 'blocks' => [{ 'type' => 'heading', 'text' => 'OS {numero}' }] })
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    expect(response.body).to start_with('%PDF')
    expect(source.reload.blocks.pluck('type')).to eq(['checklist'])
  end

  it 'gives the studio the sample data with photo addresses' do
    call(:get, 'print_templates/sample', kind: 'os')
    values = response.parsed_body['values']
    expect(values['groups']['os']['numero']).to eq('966')
    expect(values['checklist'].first['itens'].first['fotos'].first).to eq('sample' => 'amostra-1.jpg')
    expect(values['emitter']['logo_url']).to start_with('data:image/')
  end

  context 'with a real service order' do
    let(:order) do
      [{ 'NomeImpressao' => 'SOMOS', 'CPF_CNPJ' => '52346349000183', 'NomeCliente' => 'GDS', 'TipoAtendimento' => 'Manut. Corretiva',
         'NomeTecnico' => 'MARCOS', 'AvaliacaoTecnica' => 'Trocado o retentor' }]
    end
    let(:checklist) do
      [{ 'COD_SESSAO' => 1, 'DESC_SESSAO' => 'Identificação', 'ORDEM_SESSAO' => 1, 'COD_ATRIBUTO' => 10, 'DESC_ATRIBUTO' => 'Foto da plaqueta',
         'ORDEM_ATRIBUTO' => 1, 'CodigoAnexo' => 1, 'CaminhoIMG' => '966_1' },
       { 'COD_SESSAO' => 2, 'DESC_SESSAO' => 'Testes', 'ORDEM_SESSAO' => 2, 'COD_ATRIBUTO' => 20, 'DESC_ATRIBUTO' => 'Buzina',
         'ORDEM_ATRIBUTO' => 1, 'CodigoAnexo' => 2, 'CaminhoIMG' => '966_2', 'VALOR_INI' => 'OK' },
       { 'COD_SESSAO' => 2, 'DESC_SESSAO' => 'Testes', 'ORDEM_SESSAO' => 2, 'COD_ATRIBUTO' => 21, 'DESC_ATRIBUTO' => 'Outra OS',
         'ORDEM_ATRIBUTO' => 2, 'CodigoAnexo' => 3, 'CaminhoIMG' => '12_9' }]
    end
    let!(:photo_one) { stub_request(:get, %r{/getimagemchecklistos/966_1/somosemp}).to_return(status: 200, body: jpeg) }
    let!(:photo_two) { stub_request(:get, %r{/getimagemchecklistos/966_2/somosemp}).to_return(status: 200, body: jpeg) }
    let!(:other_photo) { stub_request(:get, %r{/getimagemchecklistos/12_9}).to_return(status: 200, body: jpeg) }

    before do
      { 'DadosOS_PDF' => order, 'DadosCheckIn_PDF' => [], 'DadosProdutosOS_PDF' => [], 'DadosCheckList_PDF' => checklist }.each do |endpoint, rows|
        stub_request(:get, %r{/KanbanOrdemServico/api/#{endpoint}}).to_return(status: 200, body: rows.to_json)
      end
      stub_request(:get, %r{/download-logo-empresa/}).to_return(status: 404)
      stub_request(:put, %r{/dashboard/api/query_execute}).to_return(status: 200, body: [].to_json)
    end

    it 'keeps the original report while no template is chosen' do
      call(:get, 'service_orders/report', company: 'somosemp', code: 966)
      expect(response.body).to start_with('%PDF')
      expect(photo_one).to have_been_requested.once
      expect(other_photo).not_to have_been_requested
    end

    it 'uses the template of the attendance type and fetches only the photos it shows' do
      chosen = Outsider::Erp::PrintTemplate.create!(account: account, kind: 'os', name: 'Corretiva', content: {
                                                      'blocks' => [{ 'type' => 'checklist', 'sections' => ['Testes'] },
                                                                   { 'type' => 'checklist', 'photos' => 'without' }]
                                                    })
      call(:put, 'print_templates/bindings', kind: 'os', default: 'original', types: { 'MANUT. CORRETIVA' => chosen.id })
      expect(response.parsed_body['bindings']['os']['types']).to eq('MANUT. CORRETIVA' => chosen.id)

      call(:get, 'service_orders/report', company: 'somosemp', code: 966)
      expect(response.body).to start_with('%PDF')
      expect(photo_two).to have_been_requested.once
      expect(photo_one).not_to have_been_requested
      expect(other_photo).not_to have_been_requested
    end

    it 'serves a checklist photo to the studio only for that order' do
      call(:get, 'print_templates/photo', company: 'somosemp', number: 966, ref: '966_2')
      expect(response.media_type).to eq('image/jpeg')

      call(:get, 'print_templates/photo', company: 'somosemp', number: 966, ref: '12_9')
      expect(response).to have_http_status(:not_found)
      call(:get, 'print_templates/photo', company: 'outrobanco', number: 966, ref: '966_2')
      expect(response).to have_http_status(:not_found)
      expect(other_photo).not_to have_been_requested
    end
  end
end
