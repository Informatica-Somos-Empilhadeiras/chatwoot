require 'rails_helper'

RSpec.describe 'Outsider CRM proposal catalog', type: :request do
  let(:account) { create(:account) }
  let(:product_params) do
    { product: { kind: 'machine', name: 'Empilhadeira 2,5t', code: 'CPCD25', brand: 'HELI', sale_price_cents: 12_000_000,
                 specs: [{ label: 'Capacidade', value: '2500 kg', bold: true }, { label: '', value: '' }], features: ['Motor diesel', ''] } }
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm/products" }

  before { unit.members.create!(account: account, user: seller, role: :seller) }

  def call(method, user, path = '', params = {}, as: :json)
    public_send(method, "#{base_url}#{path}", params: params, headers: user.create_new_auth_token, as: as)
    response.body.present? ? response.parsed_body : nil
  end

  it 'lets the admin register a machine, cleaning blank rows' do
    body = call(:post, admin, '', product_params)

    expect(response).to have_http_status(:created)
    expect(body['specs']).to eq([{ 'label' => 'Capacidade', 'value' => '2500 kg', 'bold' => true }])
    expect(body['features']).to eq(['Motor diesel'])
  end

  it 'keeps agents to reading until the admin allows them' do
    product = crm_product(account)
    expect(call(:get, seller).pluck('id')).to eq([product.id])

    call(:post, seller, '', product_params)
    expect(response).to have_http_status(:forbidden)

    Outsider::Crm::ProposalConfig.new(account).update_access(seller.id, view: 'own', catalog: true)
    call(:post, seller, '', product_params)
    expect(response).to have_http_status(:created)
  end

  it 'lists only active products, unless a catalog manager asks for all, and searches' do
    active = crm_product(account)
    inactive = crm_product(account, name: 'Paleteira', code: 'PT20', kind: :accessory, active: false)

    expect(call(:get, seller, '', { all: 1 }).pluck('id')).to eq([active.id])
    expect(call(:get, admin, '', { all: 1 }).pluck('id')).to contain_exactly(active.id, inactive.id)
    expect(call(:get, admin, '', { all: 1, q: 'pt20' }).pluck('id')).to eq([inactive.id])
    expect(call(:get, admin, '', { all: 1, kind: 'accessory' }).pluck('id')).to eq([inactive.id])
  end

  it 'stores the uploaded image once and swaps it' do
    product = crm_product(account)
    image = fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png')

    body = call(:put, admin, "/#{product.id}/image", { image: image }, as: nil)

    expect(response).to have_http_status(:ok)
    expect(body['image_url']).to be_present
    expect(product.reload.image).to be_attached
    expect(product.image.blob.content_type).to eq('image/png')

    call(:delete, admin, "/#{product.id}/image")
    expect(product.reload.image).not_to be_attached
  end

  it 'refuses a file that is not an image' do
    product = crm_product(account)
    file = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')

    body = call(:put, admin, "/#{product.id}/image", { image: file }, as: nil)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body['error']).to eq('invalid_image')
  end

  it 'deletes an unused product and refuses one used in a proposal' do
    unused = crm_product(account)
    used = crm_product(account, name: 'Usado')
    crm_proposal(account, owner: admin, items: [{ description: used.name, product: used, quantity: 1, unit_price_cents: 100 }])

    call(:delete, admin, "/#{unused.id}")
    expect(response).to have_http_status(:no_content)

    expect(call(:delete, admin, "/#{used.id}")).to eq('error' => 'in_use', 'reason' => 'used_in_proposals', 'count' => 1)
    expect(Outsider::Crm::Product.exists?(used.id)).to be(true)
  end
end
