# OUTSIDER: enviar um ou mais contatos (cartão de contato do WhatsApp) numa conversa de caixa da
# Evolution. Quem pode responder na conversa pode enviar (ver app/services/outsider/contact_card_sender.rb).
class Api::V1::Accounts::Outsider::ContactCardsController < Api::V1::Accounts::BaseController
  rescue_from ::Outsider::EvolutionApi::Error do |error|
    render json: { error: error.code, message: error.message }, status: :unprocessable_entity
  end

  rescue_from ::Outsider::ContactCardSender::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    authorize conversation, :show?

    message = ::Outsider::ContactCardSender.new(conversation: conversation, user: Current.user, contacts: contact_params).perform
    render json: { message_id: message&.id }
  end

  private

  def contact_params
    Array(params.require(:contacts)).map do |contact|
      contact.permit(:name, :phone, :email, :company).to_h.symbolize_keys
    end
  end
end
