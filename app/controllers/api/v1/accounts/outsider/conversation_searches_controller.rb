# OUTSIDER: busca rápida de conversas por nome ou telefone (ver app/services/outsider/conversation_search.rb).
class Api::V1::Accounts::Outsider::ConversationSearchesController < Api::V1::Accounts::BaseController
  def index
    @search = ::Outsider::ConversationSearch.new(Current.account, Current.user, params[:q])
    @conversations = @search.perform
  end
end
