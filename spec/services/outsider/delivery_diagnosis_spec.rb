require 'rails_helper'

RSpec.describe Outsider::DeliveryDiagnosis do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL') }
  let(:inbox) { channel.inbox }
  let(:customer) { create(:contact, account: account, phone_number: '+5562999990001', identifier: '5562999990001@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: customer) }
  let(:api) { instance_double(Outsider::EvolutionApi, instance: 'CENTRAL', connection_state: 'open', version: '2.3.7') }
  let(:record) do
    { 'key' => { 'id' => 'WA1', 'fromMe' => true, 'remoteJid' => '98765432101234@lid' }, 'messageType' => 'conversation',
      'messageTimestamp' => Time.current.to_i, 'message' => { 'conversation' => '*Maria:* Segue a proposta do cliente' },
      'MessageUpdate' => [{ 'status' => 'DELIVERY_ACK' }] }
  end

  around { |example| with_modified_env(OUTSIDER_DELIVERY_CHECK: 'true', EVOLUTION_API_KEY: 'chave') { example.run } }

  before do
    allow(Outsider::EvolutionApi).to receive(:new).with(inbox).and_return(api)
    allow(api).to receive_messages(find_all_messages: [record], whatsapp_numbers: [{ 'exists' => true, 'jid' => '98765432101234@lid' }])
    allow(Sidekiq::Cron::Job).to receive(:find).and_return(nil)
  end

  it 'shows both sides of each message without full phone numbers or texts' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                               content: 'Segue a proposta do cliente')

    text = described_class.new(inbox).lines.join("\n")

    expect(text).to include('instância CENTRAL', 'Agendamento no Sidekiq: NÃO ENCONTRADO', 'Evolution 2.3.7 · conexão open',
                            "##{message.id}", 'conferência=checking', 'contato=…0001@s.whatsapp.net',
                            'chat=…1234@lid', 'avisos=DELIVERY_ACK', 'mensagem=nenhuma',
                            'A Evolution manda as mensagens de …0001@s.whatsapp.net para: …1234@lid')
    expect(text).not_to include('5562999990001', 'proposta do cliente')
  end

  it 'says so when Evolution does not answer' do
    allow(api).to receive(:connection_state).and_raise(Outsider::EvolutionApi::Error, 'evolution_timeout')

    expect(described_class.new(inbox).lines.last).to eq('A Evolution não respondeu: evolution_timeout')
  end
end
