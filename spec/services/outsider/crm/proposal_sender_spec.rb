require 'rails_helper'

RSpec.describe Outsider::Crm::ProposalSender do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Ana Compras', email: 'ana@cliente.test', phone_number: '+5562999990000') }
  let(:whatsapp_inbox) { create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/somos').inbox }
  let(:email_inbox) { create(:channel_email, account: account).inbox }
  let(:proposal) { crm_proposal(account, owner: seller, contact: contact) }

  def sender(user = seller)
    described_class.new(account.account_users.find_by(user: user))
  end

  def deliver(user = seller, **params)
    defaults = { channel: 'whatsapp', contact_id: contact.id, inbox_id: whatsapp_inbox.id, message: 'Segue a proposta' }
    sender(user).deliver(proposal, defaults.merge(params))
  end

  before do
    create(:inbox_member, user: seller, inbox: whatsapp_inbox)
    create(:inbox_member, user: seller, inbox: email_inbox)
  end

  describe 'WhatsApp' do
    it 'posts the PDF in a conversation assigned to the sender, sharing the same file, and marks the proposal sent' do
      record = deliver

      message = Message.find(record.message_id)
      expect(record).to have_attributes(status: 'delivered', recipient: '+5562999990000', user_id: seller.id, contact_id: contact.id)
      expect(message).to have_attributes(content: 'Segue a proposta', message_type: 'outgoing', private: false)
      expect(message.conversation).to have_attributes(assignee_id: seller.id, inbox_id: whatsapp_inbox.id, contact_id: contact.id)
      expect(message.attachments.first.file.blob).to eq(record.document.blob)
      expect(record.document.blob).to have_attributes(content_type: 'application/pdf', filename: have_attributes(to_s: start_with('PROPOSTA')))
      expect(proposal.reload).to have_attributes(status: 'sent', sent_at: be_present)
    end

    it 'uses the open conversation the contact already has in that inbox' do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox)
      conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox)

      expect(deliver.conversation_id).to eq(conversation.id)
    end

    it 'reuses the file when the same version goes again and makes a new one after an edit' do
      first = deliver
      second = deliver
      proposal.update!(title: 'Empilhadeira 2,5t')
      third = deliver

      expect(second.document.blob.id).to eq(first.document.blob.id)
      expect(third.document.blob.id).not_to eq(first.document.blob.id)
      expect(ActiveStorage::Blob.where(content_type: 'application/pdf').count).to eq(2)
    end

    it 'logs the send on the linked deal timeline' do
      opportunity = crm_opportunity(account, crm_unit(account), contact: contact)
      proposal.update!(opportunity: opportunity)
      deliver

      expect(opportunity.activities.where(kind: :proposal).last.metadata).to include('action' => 'sent_whatsapp', 'recipient' => '+5562999990000')
    end
  end

  describe 'e-mail' do
    around { |example| with_modified_env(SMTP_ADDRESS: 'smtp.example.test') { example.run } }

    after { Outsider::Crm::ProposalMailer.delivery_method = ActionMailer::Base.delivery_method }

    it 'opens a new e-mail conversation with the subject and the PDF' do
      record = deliver(channel: 'email', inbox_id: email_inbox.id, subject: 'Proposta 1')

      conversation = Conversation.find(record.conversation_id)
      expect(record).to have_attributes(channel: 'email', recipient: 'ana@cliente.test', status: 'delivered')
      expect(conversation.additional_attributes).to include('mail_subject' => 'Proposta 1')
      expect(Message.find(record.message_id).attachments.first.file.blob).to eq(record.document.blob)
    end

    it 'goes through the Chatwoot mail server when no inbox is chosen and records the result' do
      record = nil
      expect { record = deliver(channel: 'email', inbox_id: nil, subject: 'Proposta 1') }
        .to have_enqueued_job(Outsider::Crm::ProposalMailJob)
      expect(record).to have_attributes(status: 'pending', conversation_id: nil)

      Outsider::Crm::ProposalMailer.delivery_method = :test
      expect { Outsider::Crm::ProposalMailJob.perform_now(record.id, 'Proposta 1', 'Segue') }.to change(ActionMailer::Base.deliveries, :count).by(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(['ana@cliente.test'])
      expect(mail.reply_to).to eq([seller.email])
      expect(mail.attachments.first.filename).to start_with('PROPOSTA')
      expect(record.reload.status).to eq('delivered')
    end

    it 'marks the send as failed when the mail server refuses' do
      record = deliver(channel: 'email', inbox_id: nil, subject: 'Proposta 1')
      allow(Outsider::Crm::ProposalMailer).to receive(:proposal).and_raise(Net::SMTPFatalError.new('550 recusado'))

      Outsider::Crm::ProposalMailJob.perform_now(record.id, 'Proposta 1', 'Segue')

      expect(record.reload).to have_attributes(status: 'failed', error: include('550'))
    end
  end

  describe 'blocked' do
    it 'refuses contacts without phone or e-mail and groups' do
      contact.update!(phone_number: nil, email: nil)

      expect { deliver }.to raise_error(described_class::Blocked, 'no_phone')
      expect { deliver(channel: 'email', inbox_id: email_inbox.id, subject: 'x') }.to raise_error(described_class::Blocked, 'no_email')
      group = create(:contact, account: account, identifier: '120363@g.us', phone_number: '+5562988887777')
      expect { deliver(contact_id: group.id) }.to raise_error(described_class::Blocked, 'contact')
    end

    it 'refuses e-mail without an inbox when Chatwoot has no mail server' do
      expect { deliver(channel: 'email', inbox_id: nil, subject: 'x') }.to raise_error(described_class::Blocked, 'inbox')
    end

    it 'refuses inboxes the person does not work in' do
      other = create(:channel_api, account: account, webhook_url: 'http://evolution:8080/chatwoot/webhook/outra').inbox

      expect { deliver(inbox_id: other.id) }.to raise_error(described_class::Blocked, 'inbox')
      expect(deliver(admin, inbox_id: other.id)).to be_delivered
    end

    it 'refuses canceled proposals and people who cannot edit the proposal' do
      other_seller = create(:user, account: account, role: :agent)

      expect { deliver(other_seller) }.to raise_error(described_class::Blocked, 'not_allowed')
      proposal.update!(status: :canceled)
      expect { deliver }.to raise_error(described_class::Blocked, 'not_allowed')
      expect(proposal.sends).to be_empty
    end
  end
end
