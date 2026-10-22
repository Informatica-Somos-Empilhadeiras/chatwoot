require 'rails_helper'

RSpec.describe 'Outsider CRM proposal sends', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other_seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Compras', email: 'ana@cliente.test', phone_number: '+5562999990000') }
  let(:inbox) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/somos').inbox }
  let(:proposal) { crm_proposal(account, owner: seller, contact: contact) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm/proposals/#{proposal.id}/sends" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: other_seller, role: :seller)
    create(:inbox_member, user: seller, inbox: inbox)
    create(:channel_api, account: account) # caixa de API comum não é WhatsApp
  end

  def call(method, user, path = '', params = {})
    public_send(method, "#{base_url}#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    response.body.present? ? response.parsed_body : nil
  end

  it 'lists the proposal contact, the WhatsApp inboxes the person works in, the texts and the variables' do
    no_email = create(:contact, account: account, name: 'Bruno Sem Email', phone_number: '+5562977776666')
    body = call(:get, seller, '/new')

    expect(body['contacts'].pluck('id')).to eq([contact.id])
    expect(body['contacts'].first['blocked']).to eq('whatsapp' => nil, 'email' => nil)
    expect(body['inboxes']['whatsapp'].pluck('id')).to eq([inbox.id])
    expect(body['texts']['send_message']).to include('{contato}')
    expect(body['variables']).to include('numero' => proposal.number.to_s, 'vendedor' => seller.name)

    found = call(:get, seller, '/new', q: 'Bruno')['contacts']
    expect(found.first).to include('id' => no_email.id, 'blocked' => { 'whatsapp' => nil, 'email' => 'no_email' })
  end

  it 'sends and returns the proposal with the history' do
    body = call(:post, seller, '', channel: 'whatsapp', contact_id: contact.id, inbox_id: inbox.id, message: 'Segue')

    expect(response).to have_http_status(:created)
    expect(body['status']).to eq('sent')
    expect(body['sends'].first).to include('channel' => 'whatsapp', 'recipient' => '+5562999990000', 'version' => 1,
                                           'status' => 'delivered', 'contact_name' => 'Ana Compras')
    expect(body['sends'].first['file_url']).to include('/rails/active_storage/blobs/')
    expect(body['sends'].first['conversation_display_id']).to be_present
  end

  it 'explains why a send is refused' do
    contact.update!(phone_number: nil)
    body = call(:post, seller, '', channel: 'whatsapp', contact_id: contact.id, inbox_id: inbox.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body).to include('error' => 'no_phone', 'message' => 'Este contato não tem telefone cadastrado')
  end

  it 'is only for who can edit the proposal' do
    call(:get, other_seller, '/new')
    expect(response).to have_http_status(:not_found)

    Outsider::Crm::ProposalConfig.new(account).update_access(other_seller.id, view: 'all')
    call(:get, other_seller, '/new')
    expect(response).to have_http_status(:forbidden)
  end

  describe 'accepting' do
    let(:opportunity) { crm_opportunity(account, unit, contact: contact, owner_id: seller.id) }
    let(:status_url) { "/api/v1/accounts/#{account.id}/outsider/crm/proposals/#{proposal.id}/status" }

    before { proposal.update!(opportunity: opportunity) }

    def accept
      patch status_url, params: { status: 'accepted' }, headers: seller.create_new_auth_token, as: :json
    end

    it 'leaves the deal alone by default' do
      accept

      expect(proposal.reload).to be_accepted
      expect(opportunity.reload).to be_open
    end

    it 'wins the open deal when the account turned it on' do
      Outsider::Crm::ProposalConfig.new(account).update_general(win_deal_on_accept: true)
      accept

      expect(opportunity.reload).to have_attributes(status: 'won', closed_at: be_present)
    end

    it 'does not touch a deal that is no longer open' do
      Outsider::Crm::ProposalConfig.new(account).update_general(win_deal_on_accept: true)
      opportunity.update!(status: :lost)
      accept

      expect(opportunity.reload).to be_lost
    end
  end

  it 'saves the send texts and the win option in the settings' do
    url = "/api/v1/accounts/#{account.id}/outsider/crm/proposal_settings/general"
    patch url, params: { win_deal_on_accept: true, send_message: 'Oi {contato}', email_subject: '' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('win_deal_on_accept' => true, 'next_number' => 1,
                                            'send_texts' => { 'send_message' => 'Oi {contato}', 'email_subject' => '' })
    texts = I18n.with_locale(:pt_BR) { Outsider::Crm::ProposalConfig.new(account.reload).effective_send_texts }
    expect(texts['email_subject']).to eq('Proposta {numero} - {empresa}')
  end
end
