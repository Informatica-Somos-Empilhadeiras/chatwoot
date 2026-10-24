# OUTSIDER: encaminhar uma mensagem (texto e anexos, inclusive um álbum inteiro) para um contato.
#
# Os anexos são resolvidos aqui no servidor. Antes o navegador baixava cada arquivo e mandava
# de novo, o que falhava quando o arquivo estava em outro endereço (ex.: o Dev abrindo os
# anexos da produção) e só o texto chegava. A mensagem nova reaproveita o mesmo arquivo
# (blob) da original, sem ler nem copiar nada, então funciona também no Dev, que não tem
# os arquivos da produção no disco. Apagar a mensagem original não apaga o arquivo: o
# ActiveStorage só remove um blob quando nenhum anexo usa mais ele.
#
# A mensagem vai para a conversa do contato nessa caixa que ainda não foi resolvida. Se não
# houver, abre uma nova, já atribuída a quem encaminhou. A caixa é a da conversa em que a pessoa
# está (Entrega 21); contato sem o dado que a caixa usa (telefone no WhatsApp, e-mail no e-mail)
# não recebe.
class Outsider::MessageForward
  class NothingToForward < StandardError; end
  class MissingRecipient < StandardError; end

  pattr_initialize [:account!, :user!, :contact!, :inbox!, :content, :attachment_ids]

  def perform
    attachments = source_attachments
    raise NothingToForward if content.blank? && attachments.empty?
    raise MissingRecipient unless reachable?

    signed_ids = attachments.map { |attachment| attachment.file.blob.signed_id }
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

  # a Evolution manda pelo identificador (grupo) ou pelo telefone do contato
  def reachable?
    !Outsider::EvolutionApi.evolution_inbox?(inbox) || contact.identifier.present? || contact.phone_number.present?
  end

  def target_conversation
    contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox) || build_contact_inbox
    contact_inbox.conversations.where.not(status: :resolved).order(last_activity_at: :desc).first ||
      ConversationBuilder.new(params: ActionController::Parameters.new(assignee_id: user.id), contact_inbox: contact_inbox).perform
  end

  def build_contact_inbox
    ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
  rescue ActionController::ParameterMissing
    raise MissingRecipient
  end
end
