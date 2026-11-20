require 'rails_helper'

RSpec.describe 'Outsider ERP API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:viewer) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Gilmar', additional_attributes: { 'company_name' => 'Supermercado Alvorada' }) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/erp" }
  let(:orders_json) do
    [{ 'CodigoOS' => 907, 'Empresa' => 'somosemp', 'CodigoCliente' => 716, 'Nome' => 'GDS - SUPERMERCADO ALVORADA GOIANO LTDA',
       'SubStatus' => '2-AGENDADO', 'DataEntrada' => '2026-11-11T03:00:00.000Z' },
     { 'CodigoOS' => 950, 'Empresa' => 'somosemp', 'CodigoCliente' => 716, 'Nome' => 'GDS - SUPERMERCADO ALVORADA GOIANO LTDA',
       'SubStatus' => '3-CONCLUÍDO', 'DataEntrada' => '2026-11-12T03:00:00.000Z' }].to_json
  end

  before do
    %w[os os:lock quotes quotes:lock].each { |name| Redis::Alfred.delete("outsider_erp:#{account.id}:#{name}") }
    Outsider::Erp::Settings.new(account).update('enabled' => true, 'companies' => ['somosemp'], 'write_enabled' => true)
    stub_request(:get, %r{/KanbanOrdemServico/api/valoresDash}).to_return(status: 200, body: orders_json)
    # sem resposta do banco do ERP, a gravação da OS confere pelo espelho
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return(status: 503)
    profile = Outsider::AccessProfile.create!(account: account, name: 'Só vê ERP', kind: 'custom', permissions: { 'erp' => 'view' })
    Outsider::AccessMember.create!(account: account, user: viewer, profile: profile)
  end

  it 'lists the orders of a contact once it is linked to an ERP customer' do
    get "#{url}/service_orders", params: { contact_id: contact.id }, headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('links' => [], 'orders' => [])

    post "#{url}/contact_link", params: { contact_id: contact.id, company: 'somosemp', code: 716, name: 'GDS' },
                                headers: agent.create_new_auth_token, as: :json
    get "#{url}/service_orders", params: { contact_id: contact.id }, headers: agent.create_new_auth_token
    expect(response.parsed_body['orders'].pluck('CodigoOS')).to eq([950, 907])
    expect(response.parsed_body['options']['somosemp']).to eq(%W[2-AGENDADO 3-CONCLU\u00CDDO])
  end

  it 'lets only who uses the ERP screen change an order' do
    get "#{url}/status", headers: viewer.create_new_auth_token
    expect(response.parsed_body['can_edit']).to be(false)

    put "#{url}/service_orders/substatus", params: { company: 'somosemp', code: 907, value: '3-CONCLUÍDO' },
                                           headers: viewer.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    stub_request(:put, %r{/KanbanOrdemServico/api/(UpdateSubStatusOS|GravaHistoricoSubStatusOS)/907}).to_return(status: 200, body: '[]')
    put "#{url}/service_orders/substatus", params: { company: 'somosemp', code: 907, value: '3-CONCLUÍDO' },
                                           headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['order']['SubStatus']).to eq('3-CONCLUÍDO')
  end

  it 'keeps settings for administrators and quotes loading in the background' do
    get "#{url}/settings", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)

    get "#{url}/settings", headers: admin.create_new_auth_token
    expect(response.parsed_body['settings']).not_to have_key('device_id')

    get "#{url}/quotes", params: { contact_id: contact.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:accepted)
    expect(Outsider::Erp::RefreshJob).to have_been_enqueued.with(account.id, 'quotes')
  end

  it 'follows the access profile line of each ERP tab, never above the ERP screen' do
    tabs = Outsider::AccessProfile.create!(account: account, name: 'Abas', kind: 'custom',
                                           permissions: { 'erp' => 'use', 'erp_orders' => 'view', 'erp_sales' => 'none' })
    seller = create(:user, account: account, role: :agent)
    Outsider::AccessMember.create!(account: account, user: seller, profile: tabs)

    get "#{url}/status", headers: seller.create_new_auth_token
    expect(response.parsed_body['can_edit']).to be(false)
    put "#{url}/service_orders/substatus", params: { company: 'somosemp', code: 907, value: '3-CONCLUÍDO' },
                                           headers: seller.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    get "#{url}/records/sales", headers: seller.create_new_auth_token
    expect(response.parsed_body['error']).to eq('erp_forbidden')
    get "#{url}/records/orders", headers: seller.create_new_auth_token
    expect(response).to have_http_status(:service_unavailable)

    # perfil antigo (só a tela "erp" = Vê): as abas seguem a tela e não gravam
    resolver = Outsider::Access.for(account.account_users.find_by(user: viewer))
    expect(resolver.screens.slice('erp_quotes', 'erp_orders', 'erp_sales').values).to eq(%w[view view view])
    post "#{url}/budgets", params: { contact_id: contact.id }, headers: viewer.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'refuses the quote PDF of a unit that is not in the settings' do
    Outsider::Erp::Settings.new(account).update('quotes_enabled' => true)
    get "#{url}/records/quotes/outrobanco/10/pdf", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'answers disabled when the integration is off' do
    Outsider::Erp::Settings.new(account).update('enabled' => false)
    get "#{url}/service_orders", params: { q: '907' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('erp_disabled')
  end
end
