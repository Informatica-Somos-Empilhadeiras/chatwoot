# OUTSIDER: busca rápida de conversas e contatos por nome, telefone ou e-mail (ver app/services/outsider/conversation_search.rb).
class Api::V1::Accounts::Outsider::ConversationSearchesController < Api::V1::Accounts::BaseController
  def index
    @search = ::Outsider::ConversationSearch.new(Current.account, Current.user, params[:q])
    @conversations = @search.perform.to_a
    @contacts = @search.contacts(@conversations)
    @transfers = @search.pending_transfers(@conversations)
  end
end
