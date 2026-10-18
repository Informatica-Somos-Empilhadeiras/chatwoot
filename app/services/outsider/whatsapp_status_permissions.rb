# OUTSIDER: o que cada agente pode fazer na página Status do WhatsApp. Administradores podem
# tudo; agentes só veem, a não ser que um administrador libere cada ação na aba Permissões.
# Fica em accounts.internal_attributes, que não aparece na API nem no super admin, então
# não precisa de migração.
class Outsider::WhatsappStatusPermissions
  # download e export só escondem os botões: a mídia vem pela mesma rota que mostra o status
  ALL = %w[publish republish download export].freeze
  KEY = 'outsider_whatsapp_status_permissions'.freeze

  def initialize(account)
    @account = account
  end

  def for_user(account_user)
    return ALL if account_user.administrator?

    ALL & granted.fetch(account_user.user_id.to_s, [])
  end

  def allowed?(account_user, permission)
    for_user(account_user).include?(permission)
  end

  def update(user_id, permission, allowed)
    @account.with_lock do
      current = granted.fetch(user_id.to_s, [])
      changed = granted.merge(user_id.to_s => allowed ? current | [permission] : current - [permission])
      # quem saiu da conta ou ficou sem nenhuma permissão não precisa ficar guardado
      members = @account.account_users.pluck(:user_id).map(&:to_s)
      value = changed.slice(*members).reject { |_id, list| list.empty? }
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(KEY => value)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def granted
    @account.internal_attributes.fetch(KEY, {})
  end
end
