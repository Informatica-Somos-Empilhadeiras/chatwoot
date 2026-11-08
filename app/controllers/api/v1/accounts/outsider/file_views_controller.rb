# OUTSIDER: o visualizador de documentos pede aqui como abrir um anexo (PDF, texto, Word, Excel, PowerPoint).
# Só quem pode ver a conversa recebe o endereço temporário (mesma regra de abrir a conversa).
class Api::V1::Accounts::Outsider::FileViewsController < Api::V1::Accounts::BaseController
  def show
    attachment = Attachment.find_by!(id: params[:id], account_id: Current.account.id)
    conversation = attachment.message&.conversation
    raise ActiveRecord::RecordNotFound unless conversation

    authorize conversation, :show?
    render json: ::Outsider::FileView.new(attachment).payload
  end
end
