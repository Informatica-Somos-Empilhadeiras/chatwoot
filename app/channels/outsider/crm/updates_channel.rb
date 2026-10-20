# OUTSIDER: canal das atualizações ao vivo do CRM (Outsider::Crm::LiveUpdates). Entra quem tem
# acesso ao CRM na conta, identificado como no RoomChannel do Chatwoot (pubsub_token + user_id).
class Outsider::Crm::UpdatesChannel < ApplicationCable::Channel
  def subscribed
    account_user = find_account_user
    return reject unless account_user && Outsider::Crm::Access.new(account_user).enabled?

    stream_from Outsider::Crm::LiveUpdates.stream(account_user.account_id)
  end

  private

  def find_account_user
    return if params[:pubsub_token].blank?

    user = User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
    user && AccountUser.find_by(user_id: user.id, account_id: params[:account_id])
  end
end
