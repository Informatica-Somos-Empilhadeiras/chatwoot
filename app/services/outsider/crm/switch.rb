# OUTSIDER: liga e desliga o CRM. São duas chaves, guardadas em accounts.internal_attributes (sem migração):
# - na conta: o super admin liga o CRM em Super Admin > Accounts > Edit. Toda conta começa desligada.
# - por agente: com a conta ligada, todo agente tem o CRM; o administrador da conta desliga para quem
#   não deve usar (CRM > Configurações > Acesso). Administradores da conta sempre têm.
# Quem fica desligado não vê nada do CRM (menu, aba e valor na conversa, bloco do contato), a API do CRM
# responde 403 e a pessoa sai das listas de responsável, do rodízio e dos avisos.
class Outsider::Crm::Switch
  ACCOUNT_KEY = 'outsider_crm_enabled'.freeze
  DISABLED_KEY = 'outsider_crm_disabled_user_ids'.freeze

  def self.enabled_accounts(scope = Account.all)
    scope.where("(accounts.internal_attributes ->> '#{ACCOUNT_KEY}') = 'true'")
  end

  def initialize(account)
    @account = account
  end

  def account_enabled?
    @account.internal_attributes[ACCOUNT_KEY] == true
  end

  def disabled_user_ids
    Array(@account.internal_attributes[DISABLED_KEY]).map(&:to_i)
  end

  def agent_enabled?(account_user)
    account_user.administrator? || disabled_user_ids.exclude?(account_user.user_id)
  end

  def enabled_for?(account_user)
    account_enabled? && agent_enabled?(account_user)
  end

  # Quem está com o CRM desligado de fato: a lista pode guardar alguém que depois virou administrador
  def disabled_agent_ids
    disabled_user_ids - @account.account_users.where(role: :administrator).pluck(:user_id)
  end

  def reject_disabled(user_ids)
    user_ids - disabled_agent_ids
  end

  def update_agent(user_id, enabled)
    @account.with_lock do
      ids = enabled ? disabled_user_ids - [user_id] : disabled_user_ids | [user_id]
      # quem saiu da conta não precisa ficar guardado
      ids &= @account.account_users.pluck(:user_id)
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(DISABLED_KEY => ids)) # rubocop:disable Rails/SkipsModelValidations
    end
    Outsider::Crm::LiveUpdates.broadcast(@account.id, 'access', user_id: user_id)
  end

  # Tira a pessoa da lista sem avisar ninguém (ela saiu da conta ou mudou de papel)
  def forget(user_id)
    return unless disabled_user_ids.include?(user_id)

    @account.with_lock do
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(DISABLED_KEY => disabled_user_ids - [user_id])) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
