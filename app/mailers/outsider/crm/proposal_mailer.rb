# OUTSIDER: e-mail com a proposta em anexo (ver Outsider::Crm::ProposalMailJob). Não herda do
# ApplicationMailer porque ele engole as falhas de SMTP, e aqui a falha precisa voltar para o histórico.
# Sai com o remetente do Chatwoot e o nome de quem enviou; a resposta do cliente vai para o e-mail dele.
class Outsider::Crm::ProposalMailer < ActionMailer::Base # rubocop:disable Rails/ApplicationMailer
  def proposal(record, subject, body)
    blob = record.document.blob
    attachments[blob.filename.to_s] = { mime_type: 'application/pdf', content: blob.download }
    mail(to: record.recipient, from: sender(record.user), reply_to: record.user&.email, subject: subject) do |format|
      format.text { render plain: body.presence || subject }
    end
  end

  private

  def sender(user)
    address = Mail::Address.new(ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>'))
    return address.to_s if user.blank?

    email_address_with_name(address.address, user.name)
  end
end
