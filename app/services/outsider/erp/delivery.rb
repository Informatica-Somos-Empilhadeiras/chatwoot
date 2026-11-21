# OUTSIDER: o que todo envio de PDF do ERP ao cliente tem em comum (orçamento, Outsider::Erp::BudgetSender, e relatório da
# OS, Outsider::Erp::ServiceOrderSender): o contato do WhatsApp (com telefone e que não seja grupo), a caixa, a conversa
# aberta com ele nessa caixa (ou uma nova, atribuída a quem enviou), a mensagem com o PDF, a lista de e-mails e os limites
# de tamanho. Quem inclui define @account, @user e recipients (Outsider::Erp::BudgetRecipients).
module Outsider::Erp::Delivery
  class Blocked < StandardError; end

  MAX_EMAILS = 10
  MAX_MESSAGE = 4_000
  MAX_SUBJECT = 200

  private

  def whatsapp_ready!(contact)
    raise Blocked, 'no_phone' if contact.nil? || contact.phone_number.blank? || Outsider::Crm::ContactSummary.group?(contact)

    contact
  end

  def whatsapp_inbox(inbox_id)
    recipients.whatsapp_inboxes.find { |item| item.id == inbox_id.to_i } || raise(Blocked, 'inbox')
  end

  def whatsapp_conversation(inbox, contact)
    contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox) || ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    contact_inbox.conversations.where.not(status: :resolved).order(last_activity_at: :desc).first ||
      ConversationBuilder.new(params: ActionController::Parameters.new(assignee_id: @user.id), contact_inbox: contact_inbox).perform
  end

  def post(conversation, text, attachments: [], private: false)
    params = ActionController::Parameters.new(content: text.presence, private: private, attachments: attachments)
    Messages::MessageBuilder.new(@user, conversation, params).perform
  end

  def emails(value)
    list = Array(value).flat_map { |item| item.to_s.split(/[;,\s]+/) }.compact_blank.uniq(&:downcase)
    raise Blocked, 'no_email' if list.empty?
    raise Blocked, 'too_many_emails' if list.size > MAX_EMAILS
    raise Blocked, 'invalid_email' unless list.all?(URI::MailTo::EMAIL_REGEXP)

    list
  end

  # [endereços, assunto] do e-mail, na ordem das checagens: servidor de e-mail, endereços, assunto
  def mail_target(params)
    raise Blocked, 'no_mail_server' unless recipients.system_email?

    addresses = emails(params[:to])
    subject = clean(params[:subject], MAX_SUBJECT)
    raise Blocked, 'subject_required' if subject.blank?

    [addresses, subject]
  end

  def clean(value, limit)
    text = value.to_s.strip
    raise Blocked, 'too_long' if text.size > limit

    text
  end
end
