require 'rails_helper'

RSpec.describe 'Outsider voice: deals, whisper signals and IVR admin', type: :request do
  let(:account) { create(:account) }
  let(:unit) { crm_unit(account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Transportes Silva', phone_number: '+5562999998888') }
  let!(:old_deal) { crm_opportunity(account, unit, contact: contact, owner: seller, title: 'Locação 2025') }
  let!(:new_deal) { crm_opportunity(account, unit, contact: create(:contact, account: account), owner: seller, title: 'Venda de peças') }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider" }
  let(:settings) { Outsider::Voice::Settings.new(account) }

  before do
    Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: seller, role: :seller)
    Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: manager, role: :manager)
    settings.update(
      'enabled' => true, 'ws_url' => 'wss://voip.exemplo.com.br/ws', 'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }],
      'agents' => { seller.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true },
                    manager.id.to_s => { 'extension' => '202', 'state' => 'GO', 'enabled' => true } }
    )
  end

  it 'links the call dialed from a deal to it and moves an ended call to another deal, with the timeline' do
    router = Outsider::Voice::Router.new(settings)
    router.outbound(linkedid: 'OUT1', extension: '201', number: '62999998888', deal: new_deal.id)
    call = Outsider::Voice::Call.find_by!(linkedid: 'OUT1')
    expect(call.opportunity).to eq(new_deal)

    Outsider::Voice::CallEvents.new(settings).hangup(linkedid: 'OUT1', dialstatus: 'NOANSWER', cause: '16')
    expect(new_deal.activities.where(kind: :call).count).to eq(1)

    patch "#{base}/crm/calls/#{call.id}/link", params: { opportunity_id: old_deal.id }, headers: seller.create_new_auth_token, as: :json
    expect(response.parsed_body['opportunity']).to include('id' => old_deal.id, 'title' => 'Locação 2025')
    expect(new_deal.activities.where(kind: :call).count).to eq(0)
    expect(old_deal.activities.where(kind: :call).count).to eq(1)

    get "#{base}/crm/opportunities/#{old_deal.id}/calls", headers: seller.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([call.id])
  end

  it 'links the call in progress to a deal and a new contact, found by number and start time' do
    Outsider::Voice::Router.new(settings).outbound(linkedid: 'OUT2', extension: '201', number: '62988887777')
    started = Time.current.iso8601
    other = create(:contact, account: account, name: 'Novo cliente')

    patch "#{base}/voice/call", params: { number: '62988887777', started_at: started, contact_id: other.id, opportunity_id: new_deal.id },
                                headers: seller.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('contact_id' => other.id, 'opportunity' => include('id' => new_deal.id))

    patch "#{base}/voice/call", params: { number: '62988887777', started_at: started, opportunity_id: 999_999 },
                                headers: seller.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'shows the open deals and the IVR path when the customer calls' do
    flow = Outsider::Voice::IvrFlow.create!(account: account, name: 'URA', active: true, graph: {})
    Outsider::Voice::Call.create!(account: account, linkedid: 'IN1', direction: :inbound, from_number: '+5562999998888', started_at: Time.current,
                                  ivr_flow: flow, ivr_data: { 'flow' => 'URA', 'path' => [{ 'title' => 'Menu', 'answer' => '1 - Vendas' }] })

    get "#{base}/voice/lookup", params: { number: '62999998888' }, headers: seller.create_new_auth_token
    body = response.parsed_body
    expect(body['deals'].pluck('id')).to eq([old_deal.id])
    expect(body['ivr']).to eq('flow' => 'URA', 'path' => [{ 'title' => 'Menu', 'answer' => '1 - Vendas' }])
  end

  it 'relays whisper signals only to the right person and only with a running whisper' do
    allow(Outsider::Crm::LiveUpdates).to receive(:broadcast)
    post "#{base}/voice/signal", params: { type: 'request_mode', to_user_id: seller.id, data: { mode: 'open' } },
                                 headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    Outsider::Voice::Monitor.create!(account: account, user: manager, target_user: seller, linkedid: 'W1', mode: 'whisper', kind: 'supervisor',
                                     started_at: Time.current)
    post "#{base}/voice/signal", params: { type: 'request_mode', to_user_id: seller.id, data: { mode: 'open' } },
                                 headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(Outsider::Crm::LiveUpdates).to have_received(:broadcast)
      .with(account.id, 'voice_signal', to_user_id: seller.id, signal: hash_including(type: 'apply_mode', mode: 'open'))
    expect(Outsider::Voice::Monitor.find_by!(linkedid: 'W1').opened_at).to be_present

    get "#{base}/voice/me", headers: manager.create_new_auth_token
    expect(response.parsed_body).to include('supervisor' => true, 'user_id' => manager.id)
  end

  it 'lets only administrators build IVRs and starts a new one ready to use' do
    post "#{base}/crm/ivr_flows", headers: seller.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{base}/crm/ivr_flows", params: { name: 'Principal' }, headers: admin.create_new_auth_token, as: :json
    flow = response.parsed_body
    expect(flow['graph']['nodes'].pluck('type')).to eq(%w[start say menu transfer voicemail hangup])
    expect(flow['options']['numbers']).to eq([{ 'number' => '6232345678', 'state' => 'GO', 'label' => '' }])

    patch "#{base}/crm/ivr_flows/#{flow['id']}", params: { active: true, numbers: ['(62) 3234-5678'] }, headers: admin.create_new_auth_token,
                                                 as: :json
    expect(response.parsed_body).to include('active' => true, 'numbers' => ['6232345678'])

    other = Outsider::Voice::IvrFlow.create!(account: account, name: 'Outra', graph: {})
    patch "#{base}/crm/ivr_flows/#{other.id}", params: { active: true, numbers: ['6232345678'] }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
