# OUTSIDER: envia o PDF de um orçamento do ERP (gravado pelo chat ou feito no próprio Mais Prático) para o cliente.
# - WhatsApp: na conversa aberta do contato nessa caixa (ou numa nova, atribuída a quem enviou), com a mensagem; a
#   mensagem e o registro do envio apontam para o mesmo arquivo (Outsider::Erp::BudgetDocument).
# - E-mail: para um ou vários endereços, com assunto e corpo, pelo servidor de e-mail do Chatwoot
#   (Outsider::Erp::BudgetMailJob); fica uma nota privada na conversa em que o orçamento foi feito.
# O PDF sai sempre do que está no ERP agora (Outsider::Erp::QuoteReport). O que é igual no envio da OS fica em
# Outsider::Erp::Delivery (Blocked também vem de lá).
class Outsider::Erp::BudgetSender
  include Outsider::Erp::Delivery

  CHANNELS = %w[whatsapp email].freeze

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

  # uma ou mais pessoas (até MAX_WHATSAPP; sem escolha, o contato do orçamento), um registro de envio por pessoa
  def whatsapp(budget, params)
    contacts = whatsapp_contacts!(params, fallback: budget.contact)
    inbox = whatsapp_inbox(params[:inbox_id])
    text = clean(params[:message], MAX_MESSAGE)
    whatsapp_quota!(contacts.size)
    document = document(budget)
    contacts.map { |contact| whatsapp_one(budget, document, inbox, contact, personalize(text, contact)) }.first
  end

  def whatsapp_one(budget, document, inbox, contact, text)
    Outsider::Erp::Budget.transaction do
      record = create_send(budget, document, channel: :whatsapp, recipients: [contact.phone_number])
      conversation = whatsapp_conversation(inbox, contact)
      message = post(conversation, text, attachments: [document.blob.signed_id])
      record.update!(conversation_id: conversation.id, message_id: message.id, status: :delivered)
      record
    end
  end

  def email(budget, params)
    addresses, subject = mail_target(params)
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

  def note(budget, text)
    conversation = budget.conversation_id && @account.conversations.find_by(id: budget.conversation_id)
    post(conversation, text, private: true) if conversation
  rescue StandardError => e
    Rails.logger.warn("[Outsider::Erp] nota do envio do orçamento #{budget.id}: #{e.message}")
  end

  def recipients
    @recipients ||= Outsider::Erp::BudgetRecipients.new(@account_user)
  end
end
