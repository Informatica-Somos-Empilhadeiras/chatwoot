# OUTSIDER: canal das atualizações ao vivo do CRM (Outsider::Crm::LiveUpdates), identificado como no
# RoomChannel do Chatwoot (pubsub_token + user_id). Entra qualquer pessoa da conta, mas só quem tem
# acesso ao CRM recebe os avisos de negócio, tarefa e configuração. O aviso 'access' (CRM ligado ou
# desligado na conta ou para alguém) vai para todos e faz conferir o acesso de novo: assim o CRM some
# e volta na hora, sem recarregar a página.
class Outsider::Crm::UpdatesChannel < ApplicationCable::Channel
  def subscribed
    @account_user = find_account_user
    return reject unless @account_user

    @enabled = crm_enabled?
    stream_from Outsider::Crm::LiveUpdates.stream(@account_user.account_id), coder: ActiveSupport::JSON do |message|
      relay(message)
    end
  end

  private

  def relay(message)
    access_changed = message['kind'] == 'access'
    @enabled = crm_enabled? if access_changed
    transmit(message) if @enabled || access_changed
  end

  def crm_enabled?
    account_user = AccountUser.find_by(id: @account_user.id)
    account_user.present? && Outsider::Crm::Access.new(account_user).enabled?
  end

  def find_account_user
    return if params[:pubsub_token].blank?

    user = User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
    user && AccountUser.find_by(user_id: user.id, account_id: params[:account_id])
  end
end
