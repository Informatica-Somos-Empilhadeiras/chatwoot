# OUTSIDER: busca de mensagens na conta toda, como a do WhatsApp (ver app/services/outsider/message_search.rb).
class Api::V1::Accounts::Outsider::MessageSearchesController < Api::V1::Accounts::BaseController
  def index
    render json: ::Outsider::MessageSearch.new(Current.account, Current.user, params[:q], before_id: params[:before_id]).perform
  end
end
