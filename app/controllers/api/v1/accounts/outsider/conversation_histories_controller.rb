# OUTSIDER: busca dentro da conversa, dias com mensagens (calendário) e ida até uma data.
# A conversa é carregada e autorizada pelo Conversations::BaseController (só quem pode ver a conversa).
class Api::V1::Accounts::Outsider::ConversationHistoriesController < Api::V1::Accounts::Conversations::BaseController
  def search
    render json: history.search(params[:q], since: params[:since], before: params[:until], before_id: params[:before_id])
  end

  def days
    render json: { days: history.days(params[:time_zone]) }
  end

  def locate
    message_id = history.locate(params.require(:at))
    return head :not_found if message_id.blank?

    render json: { message_id: message_id }
  end

  private

  def history
    @history ||= ::Outsider::ConversationHistory.new(@conversation)
  end
end
