# OUTSIDER: o visualizador de documentos pede aqui como abrir um anexo (PDF, texto, Word, Excel, PowerPoint) e o cartão
# do documento pede o começo do arquivo para a miniatura (peek). Só quem pode ver a conversa recebe (mesma regra de abrir
# a conversa).
class Api::V1::Accounts::Outsider::FileViewsController < Api::V1::Accounts::BaseController
  before_action :find_attachment

  def show
    render json: ::Outsider::FileView.new(@attachment).payload
  end

  def peek
    render json: ::Outsider::FilePeek.new(@attachment).payload
  end

  private

  def find_attachment
    @attachment = Attachment.find_by!(id: params[:id], account_id: Current.account.id)
    conversation = @attachment.message&.conversation
    raise ActiveRecord::RecordNotFound unless conversation

    authorize conversation, :show?
  end
end
