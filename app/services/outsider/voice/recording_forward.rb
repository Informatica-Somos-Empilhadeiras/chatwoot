# OUTSIDER: encaminhar a gravação de uma ligação para um contato pelo Chatwoot (Entrega 25), por WhatsApp ou
# e-mail. Como no envio de proposta (Outsider::Crm::ProposalSender), a mensagem aponta para o mesmo arquivo da
# gravação: nada é copiado. Quando a gravação vence (Outsider::Voice::Recording.discard), o arquivo fica para
# a conversa.
#
# WhatsApp: na conversa aberta do contato nessa caixa ou numa nova, atribuída a quem encaminhou. E-mail: numa
# conversa nova da caixa de e-mail, com assunto.
class Outsider::Voice::RecordingForward
  CHANNELS = %w[whatsapp email].freeze
  MAX_MESSAGE = 4_000

  class Blocked < StandardError; end

  def initialize(account_user, call)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
    @call = call
  end

  def recipients
    @recipients ||= Outsider::Voice::RecordingRecipients.new(@account_user, @call)
  end

  def deliver(params)
    params = params.to_h.with_indifferent_access
    raise Blocked, 'no_recording' unless @call.recording.attached?

    channel = params[:channel].to_s
    raise Blocked, 'channel' unless CHANNELS.include?(channel)

    contact = contact(params[:contact_id], channel)
    inbox = inbox(channel, params[:inbox_id])
    text = params[:message].to_s.strip
    raise Blocked, 'too_long' if text.size > MAX_MESSAGE

    post(channel == 'email' ? new_conversation(inbox, contact, mail_subject: subject) : whatsapp_conversation(inbox, contact), text)
  end

  private

  def post(conversation, text)
    params = ActionController::Parameters.new(content: text.presence, private: false, attachments: [@call.recording.blob.signed_id])
    Messages::MessageBuilder.new(@user, conversation, params).perform
    conversation
  end

  def contact(id, channel)
    contact = @account.contacts.find_by(id: id)
    raise Blocked, 'contact' if contact.nil? || Outsider::Crm::ContactSummary.group?(contact)
    raise Blocked, 'no_phone' if channel == 'whatsapp' && contact.phone_number.blank?
    raise Blocked, 'no_email' if channel == 'email' && contact.email.blank?

    contact
  end

  def inbox(channel, id)
    list = channel == 'email' ? recipients.email_inboxes : recipients.whatsapp_inboxes
    list.find { |inbox| inbox.id == id.to_i } || raise(Blocked, 'inbox')
  end

  def subject
    I18n.t('outsider_voice.recording_forward.subject', date: I18n.l(@call.started_at.in_time_zone(time_zone), format: '%d/%m/%Y %H:%M'))
  end

  def time_zone
    Outsider::Voice::Settings.new(@account).time_zone
  end

  def whatsapp_conversation(inbox, contact)
    contact_inbox(inbox, contact).conversations.where.not(status: :resolved).order(last_activity_at: :desc).first ||
      new_conversation(inbox, contact, {})
  end

  def new_conversation(inbox, contact, additional_attributes)
    params = ActionController::Parameters.new(assignee_id: @user.id, additional_attributes: additional_attributes)
    ConversationBuilder.new(params: params, contact_inbox: contact_inbox(inbox, contact)).perform
  end

  def contact_inbox(inbox, contact)
    ContactInbox.find_by(contact: contact, inbox: inbox) || ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
  end
end
