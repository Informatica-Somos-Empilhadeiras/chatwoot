# OUTSIDER: quando alguém sai da conta ou muda de papel (agente/administrador), esquece a chave do CRM
# desligado dessa pessoa (Outsider::Crm::Switch), para quem voltar ou virar agente de novo começar com o
# CRM ligado, e avisa as telas abertas para conferirem o acesso. Incluído no AccountUser pelo
# config/initializers/outsider_crm.rb.
module Outsider::Crm::AccountUserSwitch
  extend ActiveSupport::Concern

  included do
    # um callback só: dois after_commit com o mesmo método, o segundo apaga o primeiro
    after_commit :outsider_crm_access_changed, on: [:update, :destroy], if: -> { destroyed? || saved_change_to_role? }
  end

  private

  def outsider_crm_access_changed
    account = Account.find_by(id: account_id)
    return if account.nil?

    Outsider::Crm::Switch.new(account).forget(user_id)
    Outsider::Crm::LiveUpdates.broadcast(account_id, 'access', user_id: user_id)
  end
end
