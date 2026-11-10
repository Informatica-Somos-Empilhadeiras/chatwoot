require 'rails_helper'

RSpec.describe Outsider::Bot::Sender do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let(:api) { instance_double(Outsider::EvolutionApi, send_list: { 'key' => { 'id' => 'LIST' } }) }
  let(:sent) { [] }

  around { |example| with_modified_env(EVOLUTION_API_KEY: 'chave') { example.run } }

  before do
    # a cópia que a Evolution grava não chega no teste: o bot cria a mensagem sem esperar por ela
    stub_const('Outsider::Bot::Sender::ECHO_WAIT', 0.seconds)
    allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api)
    allow(api).to receive(:send_buttons) do |payload|
      sent << payload
      { 'key' => { 'id' => "WA#{sent.size}" } }
    end
  end

  def menu(count)
    options = (1..count).map { |number| { 'id' => "opt_#{number}", 'label' => "Opção #{number}", 'description' => '' } }
    { 'style' => 'buttons', 'title' => 'Por favor', 'text' => 'Escolha uma opção', 'footer' => 'Ou digite #sair',
      'button_label' => 'Ver opções', 'options' => options }
  end

  def button_ids
    sent.map { |payload| payload[:buttons].pluck(:id) }
  end

  it 'sends five options as tap buttons in two messages, the second one continuing the first' do
    described_class.new(conversation).menu(menu(5))

    expect(button_ids).to eq([%w[opt_1 opt_2 opt_3], %w[opt_4 opt_5]])
    expect(sent.first).to include(number: customer.identifier, title: 'Por favor', description: 'Escolha uma opção', footer: 'Ou digite #sair')
    expect(sent.last).to include(title: I18n.t('outsider_bot.more_options'), description: nil, footer: nil)

    messages = conversation.messages.order(:id)
    expect(messages.map(&:source_id)).to eq(%w[WAID:WA1 WAID:WA2])
    expect(messages.map { |message| message.content_attributes.dig('outsider_bot', 'options').pluck('id') }).to eq(button_ids)
    expect(messages.last.content).to include('4️⃣ Opção 4', '5️⃣ Opção 5')
    expect(messages.last.content_attributes['outsider_bot']).to include('kind' => 'menu', 'style' => 'buttons',
                                                                        'text' => I18n.t('outsider_bot.more_options'))
  end

  it 'splits four and six options evenly and keeps up to three in one message' do
    [4, 6, 3].each { |count| described_class.new(conversation).menu(menu(count)) }

    expect(button_ids.map(&:size)).to eq([2, 2, 3, 3, 3])
  end

  it 'sends more than six options as a list' do
    described_class.new(conversation).menu(menu(7))

    expect(api).to have_received(:send_list).once
    expect(sent).to be_empty
  end

  it 'falls back to the numbered text with every option when Evolution refuses the buttons' do
    allow(api).to receive(:send_buttons).and_raise(Outsider::EvolutionApi::Error, 'evolution_error')
    allow(api).to receive(:send_text).and_raise(Outsider::EvolutionApi::Error, 'evolution_error')

    described_class.new(conversation).menu(menu(5))

    expect(conversation.messages.last.content).to include('1️⃣ Opção 1', '5️⃣ Opção 5')
  end
end
