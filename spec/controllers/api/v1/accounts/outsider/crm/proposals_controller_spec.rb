require 'rails_helper'

RSpec.describe 'Outsider CRM proposals', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other_seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:other_unit) { crm_unit(account, name: 'Seminovos') }
  let!(:pipeline) { crm_pipeline(account, unit) }
  let(:contact) { create(:contact, account: account, name: 'Ana Compras', email: 'ana@cliente.test', phone_number: '+5562999990000') }
  let(:product) { crm_product(account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm/proposals" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: other_seller, role: :seller)
  end

  def call(method, user, path = '', params = {})
    public_send(method, "#{base_url}#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    response.body.present? ? response.parsed_body : nil
  end

  def proposal_params(**extra)
    { proposal: { kind: 'sale', title: 'Empilhadeira 3,5t', contact_id: contact.id, customer: { company: 'Cliente Exemplo Ltda' },
                  items: [{ product_id: product.id, quantity: 2, unit_price_cents: 10_000_000, discount_cents: 500_000 }] }.merge(extra) }
  end

  describe 'creating' do
    it 'creates a draft with the default template, items from the catalog and the total' do
      body = call(:post, seller, '', proposal_params)

      expect(response).to have_http_status(:created)
      proposal = Outsider::Crm::Proposal.find(body['id'])
      expect(proposal).to have_attributes(status: 'draft', owner_id: seller.id, created_by_id: seller.id, total_cents: 19_500_000,
                                          opportunity_id: nil)
      expect(proposal.template.name).to eq('Venda (padrão)')
      expect(proposal.items.first).to have_attributes(description: product.name, show_details: true)
      expect(proposal.items.first.details['specs'].first).to include('label' => 'Capacidade de carga')
    end

    it 'creates the deal together when asked, with the proposal total, and logs it on the timeline' do
      body = call(:post, seller, '', proposal_params(create_opportunity: { business_unit_id: unit.id, pipeline_id: pipeline.id }))

      opportunity = Outsider::Crm::Proposal.find(body['id']).opportunity
      expect(opportunity).to have_attributes(contact_id: contact.id, value_cents: 19_500_000, owner_id: seller.id)
      expect(opportunity.activities.where(kind: :proposal).last.metadata).to include('action' => 'created', 'number' => body['number'])
    end

    it 'links to a visible deal of the same contact but not to one of a unit the seller is not in' do
      mine = crm_opportunity(account, unit, contact: contact, pipeline: pipeline)
      body = call(:post, seller, '', proposal_params(opportunity_id: mine.id))
      expect(body.dig('opportunity', 'id')).to eq(mine.id)

      theirs = crm_opportunity(account, other_unit, contact: contact)
      call(:post, seller, '', proposal_params(opportunity_id: theirs.id))
      expect(response).to have_http_status(:forbidden)
    end

    it 'ignores the owner chosen by an agent but lets the admin choose' do
      call(:post, seller, '', proposal_params(owner_id: other_seller.id))
      expect(Outsider::Crm::Proposal.last.owner_id).to eq(seller.id)

      call(:post, admin, '', proposal_params(owner_id: other_seller.id))
      expect(Outsider::Crm::Proposal.last.owner_id).to eq(other_seller.id)
    end

    it 'does not let a seller use an inactive product' do
      product.update!(active: false)
      call(:post, seller, '', proposal_params)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'listing' do
    let!(:own) { crm_proposal(account, owner: seller, contact: contact, title: 'Locação 2,5t', kind: :rental) }
    let!(:theirs) { crm_proposal(account, owner: other_seller, title: 'Venda reach') }

    it 'lists only what the person may see, with the count and the total' do
      body = call(:get, seller)
      expect(body['payload'].pluck('id')).to eq([own.id])
      expect(body['meta']).to include('count' => 1, 'total_cents' => own.total_cents)

      expect(call(:get, admin)['payload'].pluck('id')).to contain_exactly(own.id, theirs.id)
    end

    it 'finds by number, customer, contact or machine and filters by kind and status' do
      expect(call(:get, admin, '', q: theirs.number.to_s)['payload'].pluck('id')).to eq([theirs.id])
      expect(call(:get, admin, '', q: 'ana compras')['payload'].pluck('id')).to eq([own.id])
      expect(call(:get, admin, '', q: 'empilhadeira')['payload'].pluck('id')).to contain_exactly(own.id, theirs.id)
      expect(call(:get, admin, '', kind: 'rental')['payload'].pluck('id')).to eq([own.id])

      own.update!(valid_until: Time.zone.yesterday)
      expect(call(:get, admin, '', status: 'expired')['payload'].pluck('id')).to eq([own.id])
    end

    it 'hides other people\'s proposals from show and pdf' do
      call(:get, seller, "/#{theirs.id}")
      expect(response).to have_http_status(:not_found)
      call(:get, seller, "/#{theirs.id}/pdf")
      expect(response).to have_http_status(:not_found)
    end

    it 'follows the visibility the admin granted' do
      Outsider::Crm::ProposalConfig.new(account).update_access(seller.id, view: 'users', user_ids: [other_seller.id])

      expect(call(:get, seller)['payload'].pluck('id')).to contain_exactly(own.id, theirs.id)
      expect(call(:get, seller, "/#{theirs.id}")['can_edit']).to be(false)
      call(:patch, seller, "/#{theirs.id}", proposal: { title: 'Outro' })
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'changing' do
    let!(:proposal) { crm_proposal(account, owner: seller, contact: contact) }

    it 'replaces the items and recalculates the total' do
      item = proposal.items.first
      items = [{ id: item.id, description: 'Máquina', quantity: 1, unit_price_cents: 5_000 },
               { description: 'Frete', quantity: 1, unit_price_cents: 1_000 }]
      body = call(:patch, seller, "/#{proposal.id}", proposal: { items: items })

      expect(body['items'].pluck('description')).to eq(%w[Máquina Frete])
      expect(body['total_cents']).to eq(6_000)
      expect(body['items'].first['id']).to eq(item.id)
    end

    it 'locks the content after the proposal is accepted, until it goes back to draft' do
      call(:patch, seller, "/#{proposal.id}/status", status: 'accepted')
      expect(proposal.reload).to have_attributes(status: 'accepted', decided_at: be_present)

      body = call(:patch, seller, "/#{proposal.id}", proposal: { title: 'Outro' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('locked')

      call(:patch, seller, "/#{proposal.id}/status", status: 'draft')
      call(:patch, seller, "/#{proposal.id}", proposal: { title: 'Outro' })
      expect(proposal.reload.title).to eq('Outro')
    end

    it 'reserves the catalog stock while accepted and gives it back when it stops being accepted' do
      machine = crm_product(account, available_quantity: 1, reserved_quantity: 0)
      untracked = crm_product(account, name: 'Garfo')
      stocked = crm_proposal(account, owner: seller, contact: contact,
                                      items: [{ description: 'Máquina', product: machine, quantity: 1.5, unit_price_cents: 100 },
                                              { description: 'Garfo', product: untracked, quantity: 1, unit_price_cents: 100 }])

      body = call(:patch, seller, "/#{stocked.id}/status", status: 'accepted')
      expect(machine.reload).to have_attributes(available_quantity: 0, reserved_quantity: 2)
      expect(untracked.reload).to have_attributes(available_quantity: nil, reserved_quantity: nil)
      expect(body['reserved_stock']).to eq([{ 'product_id' => machine.id, 'reserved' => 2, 'taken' => 1 }])

      call(:patch, seller, "/#{stocked.id}/status", status: 'rejected')
      expect(machine.reload).to have_attributes(available_quantity: 1, reserved_quantity: 0)
      expect(stocked.reload.reserved_stock).to eq([])
    end

    it 'deletes only drafts' do
      proposal.update!(status: :canceled)
      call(:delete, seller, "/#{proposal.id}")
      expect(response).to have_http_status(:forbidden)

      proposal.update!(status: :draft)
      call(:delete, seller, "/#{proposal.id}")
      expect(response).to have_http_status(:no_content)
    end

    it 'renders the PDF on demand without storing a file' do
      expect { call(:get, seller, "/#{proposal.id}/pdf") }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
      expect(response.body).to start_with('%PDF')
      expect(response.headers['Content-Disposition']).to start_with('inline')
    end
  end

  describe 'prefill' do
    it 'starts from the contact and then reuses the customer data of the last proposal' do
      body = call(:get, seller, '/prefill', contact_id: contact.id, kind: 'rental')
      expect(body).to include('kind' => 'rental', 'owner_id' => seller.id)
      expect(body['customer']).to include('company' => 'Ana Compras', 'email' => 'ana@cliente.test')
      expect(body['conditions']).to be_present

      crm_proposal(account, owner: seller, contact: contact, customer: { 'company' => 'Cliente Exemplo Ltda', 'document' => '11.111.111/0001-11' })
      body = call(:get, seller, '/prefill', contact_id: contact.id)
      expect(body['customer']).to include('company' => 'Cliente Exemplo Ltda', 'document' => '11.111.111/0001-11')
    end
  end

  it 'keeps people without the CRM out' do
    outsider = create(:user, account: account, role: :agent)
    call(:get, outsider)

    expect(response).to have_http_status(:forbidden)
  end
end
