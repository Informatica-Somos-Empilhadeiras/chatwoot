# OUTSIDER: o que todo envio de PDF do ERP ao cliente tem em comum (orçamento, Outsider::Erp::BudgetSender, e relatório da
# OS e da nota fiscal, Outsider::Erp::DocumentSender): o contato do WhatsApp (com telefone e que não seja grupo), a caixa, a conversa
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

  # a conversa que já existe com esse cliente nessa caixa; só sem nenhuma começa outra (atribuída a quem enviou)
  def whatsapp_conversation(inbox, contact)
    existing_conversation(inbox, contact) || begin
      contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox) || ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
      ConversationBuilder.new(params: ActionController::Parameters.new(assignee_id: @user.id), contact_inbox: contact_inbox).perform
    end
  end

  # procura em todos os cadastros do cliente na caixa: o mesmo contato ou outro com o mesmo celular, com e sem o 9 (a
  # Evolution às vezes cria o contato de novo), e não só no primeiro contact_inbox. Aberta, pendente ou adiada vale; com a
  # caixa travada numa conversa só (lock_to_single_conversation), vale também a última resolvida, como o Chatwoot faz.
  def existing_conversation(inbox, contact)
    contacts = @account.contacts.where(id: contact.id).or(@account.contacts.where(phone_number: phone_variants(contact.phone_number)))
    scope = @account.conversations.where(inbox_id: inbox.id, contact_id: contacts.select(:id))
    scope = scope.where.not(status: :resolved) unless inbox.lock_to_single_conversation
    scope.order(last_activity_at: :desc).first
  end

  # +55 62 99138-3950 e +55 62 9138-3950 são o mesmo celular
  def phone_variants(phone)
    phone = phone.to_s
    return [phone, "+55#{Regexp.last_match(1)}#{Regexp.last_match(2)}"] if phone =~ /\A\+55(\d{2})9(\d{8})\z/
    return [phone, "+55#{Regexp.last_match(1)}9#{Regexp.last_match(2)}"] if phone =~ /\A\+55(\d{2})([6-9]\d{7})\z/

    [phone]
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
