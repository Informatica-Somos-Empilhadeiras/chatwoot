require 'rails_helper'

# OUTSIDER: "Mostrar ordens de serviço" desligado: sem quadro, sem OS no contato e sem gravação; os vínculos ficam
# (o orçamento precisa deles). E o "Testar agora" das Configurações responde com o motivo quando o ERP falha.
RSpec.describe 'Outsider ERP service orders', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/erp" }
  let(:contact) do
    create(:contact, account: account,
                     additional_attributes: { 'outsider_erp_clients' => [{ 'empresa' => 'somosemp', 'codigo' => 716, 'nome' => 'GDS' }] })
  end
  let!(:erp_orders) do
    body = [{ 'CodigoOS' => 907, 'Empresa' => 'somosemp', 'CodigoCliente' => 716, 'Nome' => 'GDS', 'SubStatus' => '2-AGENDADO' }].to_json
    stub_request(:get, %r{/KanbanOrdemServico/api/valoresDash}).to_return(status: 200, body: body)
  end

  before do
    %w[os os:lock].each { |key| Redis::Alfred.delete("outsider_erp:#{account.id}:#{key}") }
    settings.update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc123', 'write_enabled' => true)
  end

  def call(verb, path, params = {})
    send(verb, "#{base}/#{path}", params: params, headers: admin.create_new_auth_token, as: :json)
  end

  context 'with service orders hidden' do
    before { settings.update('orders_enabled' => false) }

    it 'tells the screen and turns OS writing off' do
      call(:get, 'status')
      expect(response.parsed_body).to include('orders_enabled' => false, 'write_enabled' => false, 'can_edit' => false)
    end

    it 'refuses the board' do
      call(:get, 'service_orders/board')
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('orders_disabled')
    end

    it 'keeps the contact links but sends no orders and never asks the ERP' do
      call(:get, 'service_orders', contact_id: contact.id)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['links'].pluck('codigo')).to eq([716])
      expect(response.parsed_body['orders']).to eq([])
      expect(erp_orders).not_to have_been_requested
    end

    it 'refuses OS writes' do
      call(:put, 'service_orders/substatus', company: 'somosemp', code: 907, value: '3-CONCLUIDO')
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('write_disabled')
    end
  end

  it 'shows the orders of the contact while they are on' do
    call(:get, 'service_orders', contact_id: contact.id)
    expect(response.parsed_body['orders'].pluck('CodigoOS')).to eq([907])
  end

  it 'lists the ERP customers to link: 202 while the first copy loads, then filtered by name' do
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      sql = JSON.parse(request.body)['SQL_Execute']
      columns = %w[CodigoCliente Nome].map { |name| { 'COLUMN_NAME' => name } }
      { status: 200, body: (sql.include?('information_schema') ? columns : [{ 'codigo' => 716, 'nome' => 'GDS' }]).to_json }
    end
    call(:get, 'customers', contact_id: contact.id)
    expect(response).to have_http_status(:accepted)

    Outsider::Erp::Customers.new(account).snapshot.refresh!
    call(:get, 'customers', q: 'gds')
    expect(response.parsed_body['customers'].map { |row| row.values_at('empresa', 'codigo', 'nome') }).to eq([['somosemp', 716, 'GDS']])
  end

  describe 'settings test' do
    it 'counts the orders the ERP sent' do
      call(:post, 'settings/test')
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('orders' => 1, 'companies' => { 'somosemp' => 1 })
    end

    it 'answers with the short reason when the ERP refuses' do
      stub_request(:get, %r{/KanbanOrdemServico/api/valoresDash}).to_return(status: 403, body: '<html>blocked</html>')
      call(:post, 'settings/test')
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include('error' => 'erp_unavailable', 'message' => 'HTTP 403')
    end

    it 'says which setting is missing when no company was saved' do
      settings.update('companies' => [])
      call(:post, 'settings/test')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('no_companies')
    end
  end
end
