require 'rails_helper'

RSpec.describe 'Super Admin CRM switch per account', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'shows the CRM column in the list and on the account page' do
    get '/super_admin/accounts'
    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    # a lista do Super Admin passa o título da coluna por titleize
    expect(document.css('th').map { |header| header.text.squish }).to include('Crm')
    expect(response.body).to include(I18n.t('outsider_crm.switch.disabled'))

    get "/super_admin/accounts/#{account.id}"
    expect(Nokogiri::HTML(response.body).at_css('#outsider_crm_enabled').text.squish).to eq('CRM')
  end

  it 'turns the CRM on and off from the edit form' do
    get "/super_admin/accounts/#{account.id}/edit"
    expect(Nokogiri::HTML(response.body).at_css('input[type=checkbox][name="account[outsider_crm_enabled]"]')).to be_present

    patch "/super_admin/accounts/#{account.id}", params: { account: { name: account.name, outsider_crm_enabled: '1' } }
    expect(account.reload.outsider_crm_enabled).to be(true)

    patch "/super_admin/accounts/#{account.id}", params: { account: { name: account.name, outsider_crm_enabled: '0' } }
    expect(account.reload.outsider_crm_enabled).to be(false)
  end

  it 'creates an account with the CRM already on' do
    post '/super_admin/accounts', params: { account: { name: 'Comercial', locale: 'pt_BR', status: 'active', outsider_crm_enabled: '1' } }

    created = Account.find_by(name: 'Comercial')
    expect(created.outsider_crm_enabled).to be(true)
    expect(created.reload.internal_attributes['outsider_crm_enabled']).to be(true)
  end
end
