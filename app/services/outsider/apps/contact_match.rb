# OUTSIDER: quem é o remetente de um e-mail dos aplicativos no Chatwoot: o contato com o mesmo e-mail e a conversa mais
# recente dele, para os botões "Abrir conversa" e "Ver contato" na leitura do e-mail. Só leitura.
module Outsider::Apps::ContactMatch
  module_function

  def for(account, email)
    email = email.to_s.strip.downcase
    return nil if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)

    contact = account.contacts.from_email(email)
    return nil unless contact

    conversation = contact.conversations.order(last_activity_at: :desc).first
    { contact_id: contact.id, name: contact.name, conversation_id: conversation&.display_id }
  rescue StandardError => e
    Rails.logger.info("[outsider_apps] contact match: #{e.message}")
    nil
  end
end
