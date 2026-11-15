# OUTSIDER: a coleção de figurinhas do atendente e o envio numa conversa do WhatsApp
# (ver app/services/outsider/sticker_library.rb e sticker_sender.rb).
class Api::V1::Accounts::Outsider::StickersController < Api::V1::Accounts::BaseController
  rescue_from ::Outsider::EvolutionApi::Error do |error|
    render json: { error: error.code, message: error.message }, status: :unprocessable_entity
  end

  rescue_from ::Outsider::StickerLibrary::Invalid, ::Outsider::StickerSender::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    render json: library.list
  end

  # file (imagem subida) ou attachment_id (figurinha/foto de uma conversa que a pessoa pode ver)
  def create
    sticker, existed = if params[:attachment_id].present?
                         library.add_attachment(visible_attachment)
                       else
                         library.add_upload(params[:file])
                       end
    render json: { sticker: sticker.picker_data, existed: existed }
  end

  def update
    render json: { sticker: library.update(params[:id], params.permit(:favorite, :pack_id, :emoji)).picker_data }
  end

  def destroy
    library.destroy(params[:id])
    head :no_content
  end

  def deliver
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    authorize conversation, :show?

    message = ::Outsider::StickerSender.new(conversation: conversation, user: Current.user, sticker: library.find(params[:id])).perform
    # a mensagem vai junto para a tela mostrar na hora, sem esperar o aviso em tempo real
    render json: { message_id: message&.id, message: message&.push_event_data }
  end

  private

  def library
    @library ||= ::Outsider::StickerLibrary.new(user: Current.user, account: Current.account)
  end

  def visible_attachment
    attachment = Attachment.where(account_id: Current.account.id).find(params[:attachment_id])
    authorize attachment.message.conversation, :show?
    attachment
  end
end
