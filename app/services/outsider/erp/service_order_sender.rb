# OUTSIDER: envia o relatório de uma OS (o mesmo PDF do kanban de KPI, Outsider::Erp::ServiceOrderPdf) para o cliente,
# como o orçamento (Outsider::Erp::BudgetSender, o comum fica em Outsider::Erp::Delivery):
# - WhatsApp: na conversa aberta do contato nessa caixa (ou numa nova, atribuída a quem enviou), com a mensagem e o PDF;
# - E-mail: para um ou vários endereços pelo servidor de e-mail do Chatwoot; se o envio saiu de uma conversa, fica uma
#   nota privada nela.
# A OS não tem registro no chat, então não há histórico de envios: o WhatsApp fica na conversa e o e-mail na nota. Tudo é
# conferido antes de gerar o PDF (que baixa as fotos), para não deixar arquivo à toa quando falta telefone ou e-mail.
class Outsider::Erp::ServiceOrderSender
  include Outsider::Erp::Delivery

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
  end

  # params: channel, contact_id, inbox_id, to, subject, message; conversation: de onde o envio saiu (opcional)
  def deliver(company, code, params, conversation: nil)
    params = params.to_h.with_indifferent_access
    case params[:channel].to_s
    when 'whatsapp' then whatsapp(company, code, params)
    when 'email' then email(company, code, params, conversation)
    else raise Blocked, 'channel'
    end
  end

  private

  def whatsapp(company, code, params)
    contact = whatsapp_ready!(@account.contacts.find_by(id: params[:contact_id]))
    inbox = whatsapp_inbox(params[:inbox_id])
    text = clean(params[:message], MAX_MESSAGE)
    post(whatsapp_conversation(inbox, contact), text, attachments: [document(company, code).signed_id])
  end

  def email(company, code, params, conversation)
    addresses, subject = mail_target(params)
    body = clean(params[:message], MAX_MESSAGE)
    message = { 'to' => addresses, 'subject' => subject, 'body' => body }
    mail = Outsider::Erp::BudgetMailer.service_order(document(company, code), @account, @user, message)
    # no dev a fila vai para o Redis da produção (outro código): o e-mail sai na hora
    Rails.env.development? ? mail.deliver_now : mail.deliver_later
    note(conversation, "OS Nº #{code} enviada por e-mail para #{addresses.join(', ')}.")
  end

  def document(company, code)
    pdf = Outsider::Erp::ServiceOrderPdf.new(Outsider::Erp::ServiceOrderReport.new(@account).build(company, code))
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(pdf.render), filename: pdf.filename, content_type: 'application/pdf')
  end

  def note(conversation, text)
    post(conversation, text, private: true) if conversation
  rescue StandardError => e
    Rails.logger.warn("[Outsider::Erp] nota do envio da OS: #{e.message}")
  end

  def recipients
    @recipients ||= Outsider::Erp::BudgetRecipients.new(@account_user)
  end
end
