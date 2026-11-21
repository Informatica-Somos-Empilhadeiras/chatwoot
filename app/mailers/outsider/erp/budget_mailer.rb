# OUTSIDER: e-mail com um PDF do ERP em anexo, para um ou vários endereços: o orçamento (ver Outsider::Erp::BudgetMailJob)
# e o relatório da OS e a nota fiscal (Outsider::Erp::DocumentSender). Não herda do ApplicationMailer porque ele engole as falhas de
# SMTP, e no orçamento a falha precisa voltar para o histórico. Sai com o remetente do Chatwoot e o nome de quem enviou;
# a resposta vai para o e-mail das Configurações ou de quem enviou.
class Outsider::Erp::BudgetMailer < ActionMailer::Base # rubocop:disable Rails/ApplicationMailer
  def budget(record, subject, body)
    document_mail(record.document.blob, record.account, record.user, { 'to' => record.recipients, 'subject' => subject, 'body' => body })
  end

  # message: { 'to' => [...], 'subject' =>, 'body' => }; o PDF (OS, nota fiscal) já está no Active Storage, sem registro de envio
  def document(blob, account, user, message)
    document_mail(blob, account, user, message)
  end

  private

  def document_mail(blob, account, user, message)
    attachments[blob.filename.to_s] = { mime_type: 'application/pdf', content: blob.download }
    mail(to: message['to'], from: sender(user), reply_to: reply_to(account, user), subject: message['subject']) do |format|
      format.text { render plain: message['body'].presence || message['subject'] }
    end
  end

  def sender(user)
    address = Mail::Address.new(ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>'))
    return address.to_s if user.blank?

    email_address_with_name(address.address, user.name)
  end

  def reply_to(account, user)
    Outsider::Erp::Settings.new(account).data['quote_reply_to'].presence || user&.email
  end
end
