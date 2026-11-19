require 'rails_helper'

# OUTSIDER: POST da criação do orçamento no ERP: flag própria, acesso à proposta no CRM e motivo legível no erro
RSpec.describe 'Outsider ERP quote creation', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:proposal) { crm_proposal(account, owner: admin) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/erp/quotes" }

  before do
    settings.update('enabled' => true, 'companies' => %w[somosemp], 'quote_write_enabled' => true, 'quote_forma_pagto' => 3)
  end

  def create_quote(user)
    post url, params: { proposal_id: proposal.id }, headers: user.create_new_auth_token, as: :json
  end

  it 'does not let a person create the quote of a proposal they cannot see' do
    create_quote(agent)
    expect(response).to have_http_status(:not_found)
  end

  it 'answers 422 with the reason when the contact has no ERP customer' do
    create_quote(admin)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'quote_invalid', 'reason' => 'sem_cliente')
  end

  it 'is refused while quote writing is off' do
    settings.update('quote_write_enabled' => false)
    create_quote(admin)
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('quote_write_disabled')
  end
end
