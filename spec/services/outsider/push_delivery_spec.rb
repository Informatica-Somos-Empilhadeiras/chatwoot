require 'rails_helper'

# avisos (push) da conferência de entrega e do vigia da conexão
RSpec.describe Outsider::Push do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Vendas') }
  let(:contact) { create(:contact, account: account, name: 'Marcos Pereira') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: bruno) }
  let(:sent) { [] }

  around { |example| with_modified_env(FRONTEND_URL: 'https://chat.exemplo.com.br', OUTSIDER_PUSH: 'on') { example.run } }

  before do
    allow(VapidService).to receive_messages(public_key: 'BPublic', private_key: 'private')
    allow(WebPush).to receive(:payload_send) { |args| sent << args.merge(payload: JSON.parse(args[:message])) }
    create(:inbox_member, user: ana, inbox: inbox)
    [admin, ana, bruno].each do |user|
      user.notification_subscriptions.create!(
        subscription_type: 'browser_push', identifier: "https://push.example/#{user.id}",
        subscription_attributes: { 'endpoint' => "https://push.example/#{user.id}", 'p256dh' => 'p', 'auth' => 'a' }
      )
    end
  end

  describe Outsider::Push::UndeliveredMessage do
    let(:error) { I18n.t('outsider_delivery.unconfirmed') }

    it 'tells who sent the message, with the text and a link to the conversation' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: ana,
                                 content: 'Segue a proposta', status: :failed, content_attributes: { external_error: error })

      described_class.new(message).perform

      expect(sent.pluck(:endpoint)).to eq(["https://push.example/#{ana.id}"])
      expect(sent.first[:payload]).to include('title' => '⚠️ Mensagem não enviada · Marcos Pereira', 'tag' => "undelivered-#{conversation.id}",
                                              'path' => "/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
      expect(sent.first[:payload]['body']).to start_with('“Segue a proposta” · ')
    end

    it 'tells the assignee when the bot sent it and nobody who turned the notices off' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                 content: 'Menu', status: :failed, content_attributes: { external_error: error })
      message.update!(sender: nil)

      described_class.new(message).perform
      expect(sent.pluck(:endpoint)).to eq(["https://push.example/#{bruno.id}"])

      sent.clear
      Outsider::PushSetting.for(bruno, account).update!(prefs: { 'chatwoot' => false })
      described_class.new(message).perform
      expect(sent).to be_empty
    end
  end

  describe Outsider::Push::ConnectionNotice do
    it 'tells the agents of the inbox and the administrators that WhatsApp is down, logged out and back' do
      notice = described_class.new([inbox])

      notice.down(3)
      expect(sent.pluck(:endpoint)).to contain_exactly("https://push.example/#{ana.id}", "https://push.example/#{admin.id}")
      expect(sent.first[:payload]).to include('title' => '⚠️ WhatsApp fora do ar · WhatsApp Vendas', 'tag' => "evolution-#{inbox.id}",
                                              'path' => "/app/accounts/#{account.id}/inbox/#{inbox.id}")

      sent.clear
      notice.logged_out(401)
      notice.logged_out(403)
      notice.back(7)
      expect(sent.map { |push| push[:payload]['title'] }.uniq).to eq(
        ['🚨 WhatsApp desconectado · WhatsApp Vendas', '🚨 WhatsApp recusou a conexão · WhatsApp Vendas', '✅ WhatsApp voltou · WhatsApp Vendas']
      )
    end

    it 'sends nothing with the new push turned off' do
      with_modified_env(OUTSIDER_PUSH: 'off') { described_class.new([inbox]).down(3) }

      expect(sent).to be_empty
    end
  end
end
