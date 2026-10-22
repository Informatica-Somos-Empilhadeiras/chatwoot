# OUTSIDER: envia a proposta para um contato por WhatsApp ou e-mail. O PDF desta versão vira um arquivo só
# (Outsider::Crm::ProposalDocument), ligado ao registro do envio e à mensagem da conversa do Chatwoot: os
# dois apontam para o mesmo blob, nada é copiado (como no encaminhar). Apagar a conversa não apaga o PDF.
#
# WhatsApp: vai na conversa aberta do contato nessa caixa ou numa nova, atribuída a quem enviou.
# E-mail: com caixa de e-mail, abre uma conversa nova com o assunto; sem caixa, sai pelo servidor de e-mail
# do Chatwoot (Outsider::Crm::ProposalMailJob) e o envio fica "enviando" até o servidor responder.
# Rascunho passa para enviada e o envio aparece na linha do tempo do negócio ligado.
class Outsider::Crm::ProposalSender
  CHANNELS = %w[whatsapp email].freeze
  MAX_MESSAGE = 4_000
  MAX_SUBJECT = 200

  class Blocked < StandardError; end

  Request = Struct.new(:channel, :contact, :inbox, :text, :subject, keyword_init: true)

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
  end

  def deliver(proposal, params)
    params = params.to_h.with_indifferent_access
    raise Blocked, 'not_allowed' unless Outsider::Crm::ProposalAccess.new(@account_user).send?(proposal)

    channel = params[:channel].to_s
    raise Blocked, 'channel' unless CHANNELS.include?(channel)

    contact = recipient_contact(params[:contact_id], channel)
    inbox = inbox(channel, params[:inbox_id])
    text = clean_text(params[:message], MAX_MESSAGE)
    subject = clean_text(params[:subject], MAX_SUBJECT)
    raise Blocked, 'subject_required' if channel == 'email' && subject.blank?

    record = save(proposal, Request.new(channel: channel, contact: contact, inbox: inbox, text: text, subject: subject))
    Outsider::Crm::ProposalMailJob.perform_later(record.id, subject, text) if inbox.nil?
    record
  end

  private

  def save(proposal, request)
    document = Outsider::Crm::ProposalDocument.new(proposal)
    contact = request.contact
    Outsider::Crm::Proposal.transaction do
      blob = document.blob
      record = proposal.sends.create!(account: @account, channel: request.channel, contact_id: contact.id, user: @user, status: :pending,
                                      recipient: request.channel == 'email' ? contact.email : contact.phone_number, digest: document.digest)
      record.document.attach(blob)
      post_message(record, request, blob) if request.inbox
      mark_sent(proposal, record)
      record
    end
  end

  def post_message(record, request, blob)
    inbox = request.inbox
    contact = request.contact
    conversation = record.email? ? new_email_conversation(inbox, contact, request.subject) : whatsapp_conversation(inbox, contact)
    params = ActionController::Parameters.new(content: request.text.presence, private: false, attachments: [blob.signed_id])
    message = Messages::MessageBuilder.new(@user, conversation, params).perform
    record.update!(conversation_id: conversation.id, message_id: message.id, status: :delivered)
  end

  def whatsapp_conversation(inbox, contact)
    contact_inbox = contact_inbox(inbox, contact)
    contact_inbox.conversations.where.not(status: :resolved).order(last_activity_at: :desc).first ||
      new_conversation(contact_inbox, {})
  end

  def new_email_conversation(inbox, contact, subject)
    new_conversation(contact_inbox(inbox, contact), { mail_subject: subject })
  end

  def new_conversation(contact_inbox, additional_attributes)
    params = ActionController::Parameters.new(assignee_id: @user.id, additional_attributes: additional_attributes)
    ConversationBuilder.new(params: params, contact_inbox: contact_inbox).perform
  end

  def contact_inbox(inbox, contact)
    ContactInbox.find_by(contact: contact, inbox: inbox) || ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
  end

  def mark_sent(proposal, record)
    proposal.status = :sent if proposal.draft?
    proposal.sent_at ||= Time.current
    proposal.save!
    return unless proposal.opportunity

    proposal.opportunity.activities.create!(
      account_id: @account.id, user: @user, kind: :proposal,
      metadata: { action: "sent_#{record.channel}", proposal_id: proposal.id, number: proposal.number,
                  total_cents: proposal.total_cents, recipient: record.recipient, contact_id: record.contact_id }
    )
  end

  # Contato da conta, que não seja grupo, com telefone (WhatsApp) ou e-mail (e-mail)
  def recipient_contact(id, channel)
    contact = @account.contacts.find_by(id: id)
    raise Blocked, 'contact' if contact.nil? || Outsider::Crm::ContactSummary.group?(contact)
    raise Blocked, 'no_phone' if channel == 'whatsapp' && contact.phone_number.blank?
    raise Blocked, 'no_email' if channel == 'email' && contact.email.blank?

    contact
  end

  # Caixa que a pessoa atende e que serve para o canal; e-mail sem caixa só se o Chatwoot tem servidor de e-mail
  def inbox(channel, id)
    if id.blank?
      raise Blocked, 'inbox' unless channel == 'email' && recipients.system_email?

      return
    end

    list = channel == 'email' ? recipients.email_inboxes : recipients.whatsapp_inboxes
    list.find { |inbox| inbox.id == id.to_i } || raise(Blocked, 'inbox')
  end

  def recipients
    @recipients ||= Outsider::Crm::ProposalRecipients.new(@account_user, nil)
  end

  def clean_text(value, limit)
    text = value.to_s.strip
    raise Blocked, 'too_long' if text.size > limit

    text
  end
end
