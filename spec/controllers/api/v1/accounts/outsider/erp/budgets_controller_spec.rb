require 'rails_helper'

# OUTSIDER: API do orçamento de peças e serviços: rascunho por contato, autosave só de quem pode, "Gravar no ERP" com a
# flag própria (vai para o Sidekiq), PDF e orçamento feito no ERP importado para envio. ERP simulado (OutsiderFakeErp).
RSpec.describe 'Outsider ERP budgets API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:contact) { create(:contact, account: account, name: 'Gilmar Souza') }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/erp/budgets" }

  before do
    stub_fake_erp
    settings.update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc', 'quote_write_enabled' => true, 'quote_forma_pagto' => 3)
    Outsider::Erp::ContactLink.new(contact).add(company: 'somosemp', code: 716, name: 'ALVORADA', settings: settings)
  end

  def create_draft(user)
    post url, params: { contact_id: contact.id }, headers: user.create_new_auth_token, as: :json
    response.parsed_body['budget']
  end

  it 'opens a draft for the contact and lists it' do
    draft = create_draft(agent)
    expect(draft).to include('status' => 'draft', 'company' => 'somosemp', 'customer_code' => 716, 'can_edit' => true)

    get url, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['budgets'].pluck('id')).to eq([draft['id']])
  end

  it 'autosaves items and conditions, but only for the creator or an administrator' do
    draft = create_draft(agent)
    patch "#{url}/#{draft['id']}", params: { budget: { items: [{ codigo: 491, quantidade: 2, preco: '142,00' }], terms: { vendedor: 7 } } },
                                   headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('budget', 'items', 0)).to include('codigo' => 491, 'preco' => 142.0, 'total' => 284.0)

    other = create(:user, account: account, role: :agent)
    patch "#{url}/#{draft['id']}", params: { budget: { items: [] } }, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    patch "#{url}/#{draft['id']}", params: { budget: { items: [] } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'sends "Gravar no ERP" to the background, and refuses while quote writing is off' do
    draft = create_draft(admin)
    post "#{url}/#{draft['id']}/submit", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('budget', 'status')).to eq('submitting')
    expect(Outsider::Erp::BudgetSubmitJob).to have_been_enqueued.with(draft['id'], admin.id)

    settings.update('quote_write_enabled' => false)
    second = create_draft(admin)
    post "#{url}/#{second['id']}/submit", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('quote_write_disabled')
  end

  it 'returns the draft preview PDF and the official PDF of a quote made in the ERP' do
    draft = create_draft(agent)
    get "#{url}/#{draft['id']}/pdf", headers: agent.create_new_auth_token
    expect(response.media_type).to eq('application/pdf')

    post "#{url}/import", params: { contact_id: contact.id, company: 'somosemp', number: 3310, name: 'ALVORADA' },
                          headers: agent.create_new_auth_token, as: :json
    imported = response.parsed_body['budget']
    expect(imported).to include('status' => 'imported', 'erp_number' => 3310)

    get "#{url}/#{imported['id']}/pdf", headers: agent.create_new_auth_token
    expect(response.headers['Content-Disposition']).to include('ORCAMENTO 3310')
  end

  it 'prepares the send screen with texts and suggested e-mails' do
    post "#{url}/import", params: { contact_id: contact.id, company: 'somosemp', number: 3310 }, headers: agent.create_new_auth_token, as: :json
    get "#{url}/#{response.parsed_body.dig('budget', 'id')}/delivery", headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['texts']['subject']).to eq('Orçamento Nº 3310')
    expect(response.parsed_body['texts']['body']).to start_with('Olá, Gilmar!')
    expect(response.parsed_body.dig('recipients', 'emails')).to eq(%w[compras@alvorada.com.br nf@alvorada.com.br])
  end

  it 'lists sellers, payment terms and the fixed lists for the form, only for a configured company' do
    get "#{url}/options", params: { company: 'somosemp' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['sellers']).to eq([{ 'codigo' => 7, 'nome' => 'CRISTIANE' }])
    expect(response.parsed_body['payment_terms']).to eq([{ 'codigo' => 3, 'descricao' => '28/56/84 DIAS' }])
    expect(response.parsed_body['generos'].first).to eq('codigo' => 0, 'descricao' => 'VENDA CONSUMO')

    get "#{url}/options", params: { company: 'outrobanco' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not delete a draft that already has an ERP number' do
    draft = create_draft(agent)
    Outsider::Erp::Budget.find(draft['id']).update!(erp_number: 5001)
    delete "#{url}/#{draft['id']}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('in_erp')
  end

  it 'blocks a discount above the limit until a manager approves with the ERP code and password' do
    settings.update('quote_discount_approval' => true, 'quote_discount_line_max' => 5, 'quote_discount_total_max' => 10)
    draft = create_draft(agent)
    patch "#{url}/#{draft['id']}", params: { budget: { items: [{ codigo: 491, preco: 100, desconto: 15 }], terms: { vendedor: 7 } } },
                                   headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('budget', 'discount')).to include('needs_approval' => true, 'approved' => false, 'over_lines' => ['491'])

    post "#{url}/#{draft['id']}/submit", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('reason' => 'desconto_sem_liberacao')

    post "#{url}/#{draft['id']}/approve_discount", params: { code: 7, password: 'errada' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('error' => 'approval_refused', 'reason' => 'senha_invalida')

    post "#{url}/#{draft['id']}/approve_discount", params: { code: 7, password: 'segredo' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('budget', 'discount')).to include('approved' => true, 'approved_by' => 'CRISTIANE')
    expect(Outsider::Erp::Budget.find(draft['id']).approval.to_s).not_to include('segredo')

    post "#{url}/#{draft['id']}/submit", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('budget', 'status')).to eq('submitting')
  end
end
