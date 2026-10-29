require 'rails_helper'

RSpec.describe 'Outsider voice recordings', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Ana Compras', email: 'ana@cliente.test', phone_number: '+5562999990000') }
  let(:inbox) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/somos').inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/crm/call_recordings" }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  around { |example| travel_to(zone.local(2026, 10, 27, 15, 0)) { example.run } }

  before do
    unit = crm_unit(account)
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
    create(:inbox_member, user: seller, inbox: inbox)
    Outsider::Voice::Settings.new(account).update(
      'enabled' => true, 'agents' => { seller.id.to_s => { 'extension' => '201', 'enabled' => true },
                                       colleague.id.to_s => { 'extension' => '202', 'enabled' => true } }
    )
  end

  def recorded_call(user, attributes = {})
    call = Outsider::Voice::Call.create!({ account_id: account.id, linkedid: SecureRandom.hex(4), direction: :inbound, status: :answered,
                                           user_id: user.id, contact_id: contact.id, from_number: contact.phone_number,
                                           to_number: '6232345678', started_at: 1.hour.ago, talk_seconds: 90 }.merge(attributes))
    call.recording.attach(io: StringIO.new('webm'), filename: 'ligacao.webm', content_type: 'audio/webm')
    call
  end

  def request_as(method, user, path = '', params = {})
    public_send(method, "#{base}#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    response.parsed_body
  end

  it 'lists the recorded calls of the month that the person can see, with the date they will be deleted' do
    mine = recorded_call(seller)
    recorded_call(colleague)
    Outsider::Voice::Call.create!(account_id: account.id, linkedid: 'sem', direction: :outbound, status: :answered, user_id: seller.id,
                                  from_number: '6232345678', to_number: '62999990000', started_at: 1.hour.ago)

    body = request_as(:get, seller, '', month: '2026-10')

    expect(body['payload'].pluck('id')).to eq([mine.id])
    expect(body['payload'].first).to include('contact_name' => 'Ana Compras', 'byte_size' => 4, 'expires_on' => '2027-10-27')
    expect(body['meta']).to include('total' => 1, 'days' => 365, 'bytes' => 4)
    expect(request_as(:get, admin, '', month: '2026-10')['meta']['total']).to eq(2)
    expect(request_as(:get, admin, '', month: '2026-10', q: 'Ana')['meta']['total']).to eq(2)
    expect(request_as(:get, admin, '', month: '2026-09')['meta']['total']).to eq(0)
  end

  it 'forwards the recording by WhatsApp pointing to the same file' do
    call = recorded_call(seller)

    options = request_as(:get, seller, "/#{call.id}/forward")
    expect(options['contacts'].pluck('id')).to eq([contact.id])
    expect(options['inboxes']['whatsapp'].pluck('id')).to eq([inbox.id])

    body = request_as(:post, seller, "/#{call.id}/forward", channel: 'whatsapp', contact_id: contact.id, inbox_id: inbox.id,
                                                            message: 'Segue a gravação')
    expect(response).to have_http_status(:created)
    message = Conversation.find_by(display_id: body['conversation_id'], account_id: account.id).messages.last
    expect(message.content).to eq('Segue a gravação')
    expect(message.attachments.first.file.blob).to eq(call.recording.blob)
  end

  it 'refuses to forward to a contact without phone, or a call the person cannot see' do
    call = recorded_call(seller)
    no_phone = create(:contact, account: account, name: 'Sem Telefone', email: 'x@cliente.test')

    body = request_as(:post, seller, "/#{call.id}/forward", channel: 'whatsapp', contact_id: no_phone.id, inbox_id: inbox.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(body['error']).to eq('no_phone')

    request_as(:get, colleague, "/#{call.id}/forward")
    expect(response).to have_http_status(:not_found)
  end
end
