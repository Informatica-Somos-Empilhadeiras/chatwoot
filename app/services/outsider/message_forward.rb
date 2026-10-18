# OUTSIDER: encaminhar uma mensagem (texto e anexos, inclusive um álbum inteiro) para um contato.
#
# Os anexos são copiados aqui no servidor. Antes o navegador baixava cada arquivo e mandava
# de novo, o que falhava quando o arquivo estava em outro endereço (ex.: o Dev abrindo os
# anexos da produção) e só o texto chegava. Cada cópia é um arquivo novo, então apagar a
# mensagem original não apaga o anexo encaminhado.
#
# A mensagem vai para a conversa do contato nessa caixa que ainda não foi resolvida. Se não
# houver, abre uma nova, já atribuída a quem encaminhou.
class Outsider::MessageForward
  class NothingToForward < StandardError; end

  pattr_initialize [:account!, :user!, :contact!, :inbox!, :source_id, :content, :attachment_ids]

  def perform
    attachments = source_attachments
    raise NothingToForward if content.blank? && attachments.empty?

    signed_ids = attachments.map { |attachment| copy(attachment) }
    ActiveRecord::Base.transaction do
      params = ActionController::Parameters.new(content: content, private: false, attachments: signed_ids)
      Messages::MessageBuilder.new(user, target_conversation, params).perform
    end
  end

  private

  # só anexos de conversas que a pessoa pode ver, na ordem em que vieram
  def source_attachments
    ids = Array(attachment_ids).map(&:to_i).uniq
    attachments = Attachment.where(account_id: account.id, id: ids).includes(:message, file_attachment: :blob).to_a
    raise Pundit::NotAuthorizedError if attachments.size != ids.size || !visible?(attachments)

    attachments.sort_by { |attachment| ids.index(attachment.id) }
  end

  def visible?(attachments)
    conversation_ids = attachments.map { |attachment| attachment.message.conversation_id }.uniq
    scope = account.conversations.where(id: conversation_ids)
    Conversations::PermissionFilterService.new(scope, user, account).perform.count == conversation_ids.size
  end

  def copy(attachment)
    blob = attachment.file.blob
    blob.open do |file|
      ActiveStorage::Blob.create_and_upload!(io: file, filename: blob.filename, content_type: blob.content_type).signed_id
    end
  end

  def target_conversation
    contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox) ||
                    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: source_id).perform
    contact_inbox.conversations.where.not(status: :resolved).order(last_activity_at: :desc).first ||
      ConversationBuilder.new(params: ActionController::Parameters.new(assignee_id: user.id), contact_inbox: contact_inbox).perform
  end
end
