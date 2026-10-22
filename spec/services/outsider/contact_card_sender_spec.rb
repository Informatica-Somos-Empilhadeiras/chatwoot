require 'rails_helper'

RSpec.describe Outsider::ContactCardSender do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let(:api) { instance_double(Outsider::EvolutionApi) }
  let(:contacts) { [{ name: '  Daniel  Comercial ', phone: '(62) 9183-4188', company: 'Somos' }] }

  before do
    stub_const('Outsider::ContactCardSender::ECHO_WAIT', 0.seconds)
    allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api)
    allow(api).to receive(:whatsapp_numbers).and_return([{ 'exists' => true, 'jid' => '556291834188@s.whatsapp.net', 'number' => '556291834188' }])
  end

  def sender(list = contacts)
    described_class.new(conversation: conversation, user: agent, contacts: list)
  end

  it 'sends a vCard to the conversation number with the WhatsApp id of each contact' do
    allow(api).to receive(:send_contact).and_return({ 'key' => { 'id' => 'ABC' } })

    sender.perform

    expect(api).to have_received(:send_contact).with(
      number: '5562999990001@s.whatsapp.net',
      contact: [{ fullName: 'Daniel Comercial', wuid: '556291834188', phoneNumber: '+55 62 9183-4188', organization: 'Somos' }]
    )
  end

  it 'puts the agent and the card data on the message Evolution records' do
    echo = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, source_id: 'WAID:ABC',
                            content: "*Contato:*\n\n_Nome:_ Daniel Comercial\n_Número (1):_ +55 62 9183-4188")
    allow(api).to receive(:send_contact).and_return({ 'key' => { 'id' => 'ABC' } })

    expect(sender.perform).to eq(echo)

    echo.reload
    expect(echo.sender).to eq(agent)
    expect(echo.content_attributes['outsider_contacts']).to eq(
      [{ 'name' => 'Daniel Comercial', 'waid' => '556291834188', 'company' => 'Somos', 'phone' => '+55 62 9183-4188' }]
    )
  end

  it 'keeps the typed number when it is not on WhatsApp' do
    allow(api).to receive(:whatsapp_numbers).and_return([{ 'exists' => false, 'number' => '5511988887777' }])
    allow(api).to receive(:send_contact).and_return({})

    sender([{ name: 'Ana', phone: '+55 11 98888-7777' }]).perform

    expect(api).to have_received(:send_contact)
      .with(hash_including(contact: [hash_including(wuid: '5511988887777', phoneNumber: '+55 11 98888-7777')]))
  end

  it 'refuses bad input and inboxes that are not Evolution' do
    expect { sender([{ name: 'Ana', phone: '123' }]).perform }.to raise_error(described_class::Invalid, 'invalid_phone')
    expect { sender([{ name: '', phone: '62991834188' }]).perform }.to raise_error(described_class::Invalid, 'missing_name')
    expect { sender([]).perform }.to raise_error(described_class::Invalid, 'no_contacts')
    many = Array.new(11) { |index| { name: "C#{index}", phone: "6299183#{index.to_s.rjust(4, '0')}" } }
    expect { sender(many).perform }.to raise_error(described_class::Invalid, 'too_many_contacts')

    channel.update!(webhook_url: 'https://example.com/hook')
    expect { sender.perform }.to raise_error(described_class::Invalid, 'not_evolution')
  end
end
