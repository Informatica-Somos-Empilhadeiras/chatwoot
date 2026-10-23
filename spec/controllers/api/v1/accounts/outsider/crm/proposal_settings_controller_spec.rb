require 'rails_helper'

RSpec.describe 'Outsider CRM proposal settings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other_seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: other_seller, role: :seller)
  end

  def call(method, user, path, params = {})
    public_send(method, "#{base_url}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    response.body.present? ? response.parsed_body : nil
  end

  it 'is only for admins' do
    call(:get, seller, 'proposal_settings')
    expect(response).to have_http_status(:forbidden)
    call(:patch, seller, 'proposal_settings/general', next_number: 10)
    expect(response).to have_http_status(:forbidden)
  end

  it 'sets the next number and refuses nonsense' do
    expect(call(:patch, admin, 'proposal_settings/general', next_number: 2661)['next_number']).to eq(2661)

    call(:patch, admin, 'proposal_settings/general', next_number: 'abc')
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'starts with the default payment options, which only the admin changes and everyone reads' do
    expect(call(:get, seller, 'proposal_payment_options')['payload']).to eq(['A VISTA', '30% + 06X NO BOLETO', 'CARTÃO DE CRÉDITO'])

    body = call(:patch, admin, 'proposal_settings/general', payment_options: ['  A VISTA ', '50% +  03X NO BOLETO', '', 'A VISTA'])
    expect(body['payment_options']).to eq(['A VISTA', '50% + 03X NO BOLETO'])
    expect(call(:get, seller, 'proposal_payment_options')['payload']).to eq(['A VISTA', '50% + 03X NO BOLETO'])

    expect(call(:patch, admin, 'proposal_settings/general', payment_options: [])['payment_options']).to eq([])

    call(:patch, admin, 'proposal_settings/general', payment_options: ['x' * 201])
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps company data per unit on top of the default' do
    call(:patch, admin, 'proposal_settings/company', company: { legal_name: 'Matriz Ltda', city: 'Goiânia' })
    body = call(:patch, admin, 'proposal_settings/company', unit_id: unit.id, company: { city: 'Brasília', legal_name: '' })

    expect(body['company']).to include('legal_name' => 'Matriz Ltda', 'city' => 'Goiânia')
    expect(body['unit_companies'][unit.id.to_s]).to eq('city' => 'Brasília')
    expect(Outsider::Crm::ProposalConfig.new(account.reload).company(unit.id)).to include('legal_name' => 'Matriz Ltda', 'city' => 'Brasília')
  end

  it 'saves who sees whose proposals, ignoring people from other accounts' do
    stranger = create(:user)
    body = call(:patch, admin, "proposal_settings/access/#{seller.id}", access: { view: 'users', user_ids: [other_seller.id, stranger.id],
                                                                                  catalog: true })

    person = body['people'].find { |row| row['id'] == seller.id }
    expect(person['access']).to eq('view' => 'users', 'user_ids' => [other_seller.id], 'catalog' => true)

    call(:patch, admin, "proposal_settings/access/#{stranger.id}", access: { view: 'all' })
    expect(response).to have_http_status(:not_found)
  end

  it 'lets each person keep their own signature and the admin edit anyone\'s' do
    call(:patch, seller, 'proposal_signature', signature: { title: 'Consultora', phone: '(62) 0000-0000' })
    expect(call(:get, seller, 'proposal_signature')).to include('title' => 'Consultora')

    body = call(:patch, admin, "proposal_settings/signatures/#{seller.id}", signature: { title: 'Gerente' })
    expect(body['people'].find { |row| row['id'] == seller.id }['signature']).to include('title' => 'Gerente')
  end

  it 'creates the two default templates on the first visit and lets only admins change them' do
    templates = call(:get, seller, 'proposal_templates')
    expect(templates.pluck('name')).to contain_exactly('Venda (padrão)', 'Locação (padrão)')

    sale = templates.find { |row| row['kind'] == 'sale' }
    call(:patch, seller, "proposal_templates/#{sale['id']}", proposal_template: { name: 'X' })
    expect(response).to have_http_status(:forbidden)

    body = call(:patch, admin, "proposal_templates/#{sale['id']}", proposal_template: { content: { intro: 'Olá {cliente.empresa}' } })
    expect(body.dig('content', 'intro')).to eq('Olá {cliente.empresa}')
    expect(body.dig('content', 'conditions')).to be_present
  end
end
