require 'rails_helper'

RSpec.describe 'Outsider CRM company lookup', type: :request do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/company_lookup" }

  before { crm_unit(account).members.create!(account: account, user: seller, role: :seller) }

  def lookup(user, document)
    get url, params: { document: document }, headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'answers the proposal fields and turns the lookup failures into codes' do
    lookup_double = instance_double(Outsider::Crm::CompanyLookup, perform: { customer: { 'company' => 'SOMOS LTDA' }, sources: ['cnpja'] })
    allow(Outsider::Crm::CompanyLookup).to receive(:new).and_call_original
    allow(Outsider::Crm::CompanyLookup).to receive(:new).with('11222333000181').and_return(lookup_double)

    expect(lookup(seller, '11222333000181')).to eq('customer' => { 'company' => 'SOMOS LTDA' }, 'sources' => ['cnpja'])

    expect(lookup(seller, '123')).to eq('error' => 'invalid_document')
    expect(response).to have_http_status(:unprocessable_entity)

    allow(lookup_double).to receive(:perform).and_raise(Outsider::Crm::CompanyLookup::Unavailable)
    expect(lookup(seller, '11222333000181')).to eq('error' => 'unavailable')
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'is only for people with the CRM' do
    lookup(outsider, '11222333000181')
    expect(response).to have_http_status(:forbidden)
  end
end
