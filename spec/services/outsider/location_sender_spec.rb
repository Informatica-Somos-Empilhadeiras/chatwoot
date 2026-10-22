require 'rails_helper'

RSpec.describe Outsider::LocationSender do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let(:api) { instance_double(Outsider::EvolutionApi) }
  let(:location) { { name: '  Somos  Goiânia ', address: 'Av. Anhanguera, 100 - Goiânia', latitude: '-16,6869', longitude: '-49.2648123456' } }

  before do
    stub_const('Outsider::LocationSender::ECHO_WAIT', 0.seconds)
    allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api)
  end

  def sender(place = location)
    described_class.new(conversation: conversation, user: agent, location: place)
  end

  it 'sends the pin to the conversation number with clean coordinates' do
    allow(api).to receive(:send_location).and_return({ 'key' => { 'id' => 'LOC1' } })

    sender.perform

    expect(api).to have_received(:send_location).with(
      number: '5562999990001@s.whatsapp.net', latitude: -16.6869, longitude: -49.264812,
      name: 'Somos Goiânia', address: 'Av. Anhanguera, 100 - Goiânia'
    )
  end

  it 'puts the agent and the place on the message Evolution records' do
    echo = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, source_id: 'WAID:LOC1',
                            content: "*Localização:*\n\n_Latitude:_ -16.6869 \n_Longitude:_ -49.264812 \n")
    allow(api).to receive(:send_location).and_return({ 'key' => { 'id' => 'LOC1' } })

    expect(sender.perform).to eq(echo)

    echo.reload
    expect(echo.sender).to eq(agent)
    expect(echo.content_attributes['outsider_location']).to eq(
      'latitude' => -16.6869, 'longitude' => -49.264812, 'name' => 'Somos Goiânia', 'address' => 'Av. Anhanguera, 100 - Goiânia'
    )
  end

  it 'sends without name and address' do
    allow(api).to receive(:send_location).and_return({})

    sender({ latitude: -23.55, longitude: -46.63 }).perform

    expect(api).to have_received(:send_location).with(number: '5562999990001@s.whatsapp.net', latitude: -23.55, longitude: -46.63,
                                                      name: nil, address: nil)
  end

  it 'refuses bad coordinates, contacts without number and inboxes that are not Evolution' do
    expect { sender({ latitude: '91', longitude: '10' }).perform }.to raise_error(described_class::Invalid, 'invalid_coordinates')
    expect { sender({ latitude: 'abc', longitude: '10' }).perform }.to raise_error(described_class::Invalid, 'invalid_coordinates')

    customer.update!(identifier: nil, phone_number: nil)
    expect { sender.perform }.to raise_error(described_class::Invalid, 'no_recipient')

    channel.update!(webhook_url: 'https://example.com/hook')
    expect { sender.perform }.to raise_error(described_class::Invalid, 'not_evolution')
  end
end
