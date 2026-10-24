# OUTSIDER: reagir e editar mensagem do WhatsApp nas caixas da Evolution (ver app/services/outsider/whatsapp_message_actions.rb).
# Quem pode ver a conversa reage; editar fica para quem enviou ou um administrador.
class Api::V1::Accounts::Outsider::WhatsappMessagesController < Api::V1::Accounts::BaseController
  rescue_from ::Outsider::EvolutionApi::Error do |error|
    render json: { error: error.code, message: error.message }, status: :unprocessable_entity
  end

  rescue_from ::Outsider::WhatsappMessageActions::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  before_action :fetch_message

  def update
    message = actions.edit(params.require(:content))
    render json: { message: message.push_event_data }
  end

  def reaction
    actions.react(params[:emoji])
    head :no_content
  end

  private

  def fetch_message
    @message = Current.account.messages.find(params[:id])
    authorize @message.conversation, :show?
  end

  def actions
    ::Outsider::WhatsappMessageActions.new(message: @message, account_user: Current.account_user)
  end
end
