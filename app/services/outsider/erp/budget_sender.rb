# OUTSIDER: envia o PDF de um orçamento do ERP (gravado pelo chat ou feito no próprio Mais Prático) para o cliente.
# - WhatsApp: na conversa aberta do contato nessa caixa (ou numa nova, atribuída a quem enviou), com a mensagem; a
#   mensagem e o registro do envio apontam para o mesmo arquivo (Outsider::Erp::BudgetDocument).
# - E-mail: para um ou vários endereços, com assunto e corpo, pelo servidor de e-mail do Chatwoot
#   (Outsider::Erp::BudgetMailJob); fica uma nota privada na conversa em que o orçamento foi feito.
# O PDF sai sempre do que está no ERP agora (Outsider::Erp::QuoteReport).
class Outsider::Erp::BudgetSender
  class Blocked < StandardError; end

  CHANNELS = %w[whatsapp email].freeze
  MAX_EMAILS = 10
  MAX_MESSAGE = 4_000
  MAX_SUBJECT = 200

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
  end

  def deliver(budget, params)
    params = params.to_h.with_indifferent_access
    raise Blocked, 'not_in_erp' unless budget.in_erp?

    case params[:channel].to_s
    when 'whatsapp' then whatsapp(budget, params)
    when 'email' then email(budget, params)
    else raise Blocked, 'channel'
    end
  end

  private

  def whatsapp(budget, params)
    contact = whatsapp_contact(budget, params[:contact_id])
    inbox = recipients.whatsapp_inboxes.find { |item| item.id == params[:inbox_id].to_i } || raise(Blocked, 'inbox')
    text = clean(params[:message], MAX_MESSAGE)
    document = document(budget)
    Outsider::Erp::Budget.transaction do
      record = create_send(budget, document, channel: :whatsapp, recipients: [contact.phone_number])
      conversation = whatsapp_conversation(inbox, contact)
      message = post(conversation, text, attachments: [document.blob.signed_id])
      record.update!(conversation_id: conversation.id, message_id: message.id, status: :delivered)
      record
    end
  end

  # outro contato escolhido na busca, senão o do orçamento; precisa ter telefone e não ser grupo
  def whatsapp_contact(budget, contact_id)
    contact = contact_id.present? ? @account.contacts.find_by(id: contact_id) : budget.contact
    raise Blocked, 'no_phone' if contact.nil? || contact.phone_number.blank? || Outsider::Crm::ContactSummary.group?(contact)

    contact
  end

  def email(budget, params)
    raise Blocked, 'no_mail_server' unless recipients.system_email?

    addresses = emails(params[:to])
    subject = clean(params[:subject], MAX_SUBJECT)
    raise Blocked, 'subject_required' if subject.blank?

    body = clean(params[:message], MAX_MESSAGE)
    record = create_send(budget, document(budget), channel: :email, recipients: addresses, subject: subject)
    deliver_mail(record, subject, body)
    note(budget, "Orçamento Nº #{budget.erp_number} enviado por e-mail para #{addresses.join(', ')}.")
    record
  end

  def document(budget)
    Outsider::Erp::BudgetDocument.new(budget, Outsider::Erp::QuoteReport.new(@account).build(budget.company, budget.erp_number))
  end

  def create_send(budget, document, channel:, recipients:, subject: nil)
    record = budget.sends.create!(account: @account, user: @user, channel: channel, recipients: recipients, subject: subject,
                                  status: :pending, digest: document.tap(&:blob).digest)
    record.document.attach(document.blob)
    record
  end

  # no dev a fila vai para o Redis da produção (outro código): o e-mail sai na hora
  def deliver_mail(record, subject, body)
    return Outsider::Erp::BudgetMailJob.perform_now(record.id, subject, body) if Rails.env.development?

    Outsider::Erp::BudgetMailJob.perform_later(record.id, subject, body)
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

  def note(budget, text)
    conversation = budget.conversation_id && @account.conversations.find_by(id: budget.conversation_id)
    post(conversation, text, private: true) if conversation
  rescue StandardError => e
    Rails.logger.warn("[Outsider::Erp] nota do envio do orçamento #{budget.id}: #{e.message}")
  end

  def emails(value)
    list = Array(value).flat_map { |item| item.to_s.split(/[;,\s]+/) }.compact_blank.uniq(&:downcase)
    raise Blocked, 'no_email' if list.empty?
    raise Blocked, 'too_many_emails' if list.size > MAX_EMAILS
    raise Blocked, 'invalid_email' unless list.all?(URI::MailTo::EMAIL_REGEXP)

    list
  end

  def recipients
    @recipients ||= Outsider::Erp::BudgetRecipients.new(@account_user)
  end

  def clean(value, limit)
    text = value.to_s.strip
    raise Blocked, 'too_long' if text.size > limit

    text
  end
end
