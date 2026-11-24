# OUTSIDER: envia um PDF do ERP para o cliente, como o orçamento (Outsider::Erp::BudgetSender, o comum fica em
# Outsider::Erp::Delivery): o relatório da OS e a nota fiscal (NF-e/NFS-e) espelhada do Nextcloud.
# - WhatsApp: na conversa aberta do contato nessa caixa (ou numa nova, atribuída a quem enviou), com a mensagem e o PDF;
# - E-mail: para um ou vários endereços pelo servidor de e-mail do Chatwoot; se o envio saiu de uma conversa, fica uma
#   nota privada nela.
# Esses documentos não têm registro no chat, então não há histórico de envios: o WhatsApp fica na conversa e o e-mail na
# nota. Tudo é conferido antes de buscar o documento (que gera o PDF ou baixa do Nextcloud), para não deixar arquivo à
# toa quando falta telefone ou e-mail.
class Outsider::Erp::DocumentSender
  include Outsider::Erp::Delivery

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
  end

  # params: channel, contact_id, inbox_id, to, subject, message; document: o que devolve { 'filename', 'content' } do PDF
  # (só chamado depois de tudo conferido); label: o documento na nota do e-mail ("OS Nº 850"); conversation: de onde o
  # envio saiu (opcional)
  def deliver(params, document:, label:, conversation: nil)
    params = params.to_h.with_indifferent_access
    case params[:channel].to_s
    when 'whatsapp' then whatsapp(params, document)
    when 'email' then email(params, document, label, conversation)
    else raise Blocked, 'channel'
    end
  end

  private

  # uma ou mais pessoas (até MAX_WHATSAPP), o mesmo PDF para todas, cada uma na conversa dela
  def whatsapp(params, document)
    contacts = whatsapp_contacts!(params)
    inbox = whatsapp_inbox(params[:inbox_id])
    text = clean(params[:message], MAX_MESSAGE)
    whatsapp_quota!(contacts.size)
    file = blob(document)
    contacts.each { |contact| post(whatsapp_conversation(inbox, contact), personalize(text, contact), attachments: [file.signed_id]) }
  end

  def email(params, document, label, conversation)
    addresses, subject = mail_target(params)
    body = clean(params[:message], MAX_MESSAGE)
    message = { 'to' => addresses, 'subject' => subject, 'body' => body }
    mail = Outsider::Erp::BudgetMailer.document(blob(document), @account, @user, message)
    # no dev a fila vai para o Redis da produção (outro código): o e-mail sai na hora
    Rails.env.development? ? mail.deliver_now : mail.deliver_later
    note(conversation, "#{label} enviada por e-mail para #{addresses.join(', ')}.")
  end

  def blob(document)
    file = document.call
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(file['content']), filename: file['filename'], content_type: 'application/pdf')
  end

  def note(conversation, text)
    post(conversation, text, private: true) if conversation
  rescue StandardError => e
    Rails.logger.warn("[Outsider::Erp] nota do envio: #{e.message}")
  end

  def recipients
    @recipients ||= Outsider::Erp::BudgetRecipients.new(@account_user)
  end
end
