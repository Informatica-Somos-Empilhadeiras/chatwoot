# OUTSIDER: e-mail com o orçamento do ERP em anexo (ver Outsider::Erp::BudgetMailJob), para um ou vários endereços.
# Não herda do ApplicationMailer porque ele engole as falhas de SMTP, e aqui a falha precisa voltar para o histórico.
# Sai com o remetente do Chatwoot e o nome de quem enviou; a resposta vai para o e-mail das Configurações ou de quem enviou.
class Outsider::Erp::BudgetMailer < ActionMailer::Base # rubocop:disable Rails/ApplicationMailer
  def budget(record, subject, body)
    blob = record.document.blob
    attachments[blob.filename.to_s] = { mime_type: 'application/pdf', content: blob.download }
    mail(to: record.recipients, from: sender(record.user), reply_to: reply_to(record), subject: subject) do |format|
      format.text { render plain: body.presence || subject }
    end
  end

  private

  def sender(user)
    address = Mail::Address.new(ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>'))
    return address.to_s if user.blank?

    email_address_with_name(address.address, user.name)
  end

  def reply_to(record)
    Outsider::Erp::Settings.new(record.account).data['quote_reply_to'].presence || record.user&.email
  end
end
