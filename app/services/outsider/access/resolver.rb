# OUTSIDER: o acesso de uma pessoa numa conta, tela por tela (ver Outsider::Access). Administrador do Chatwoot vê tudo;
# os demais seguem o perfil (o escolhido ou o padrão do tipo), sem passar do que o superadministrador liberou na conta.
class Outsider::Access::Resolver
  Catalog = Outsider::Access::Catalog

  attr_reader :account_user

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
  end

  def administrator? = @account_user.administrator?

  def profile
    return @profile if defined?(@profile)

    @profile = if administrator?
                 Outsider::Access::Defaults.new(@account).ensure!.find_by(kind: 'administrator')
               else
                 Outsider::AccessMember.includes(:profile).find_by(account_id: @account.id, user_id: @account_user.user_id)&.profile ||
                   Outsider::Access::Defaults.new(@account).default_for('agent')
               end
  end

  # tela filha (as abas da seção ERP) nunca passa da tela mãe
  def level(screen)
    screen = screen.to_s
    parent = Catalog.parent(screen)
    parent ? [own_level(screen), level(parent)].min_by { |item| Catalog.rank(item) } : own_level(screen)
  end

  def own_level(screen)
    return Catalog.levels(screen).max_by { |item| Catalog.rank(item) } || 'none' if administrator?
    return 'none' if Catalog.admin_only?(screen) || admin_only_screens.include?(screen)

    profile ? profile.level(screen) : Catalog.default_level('agent', screen)
  end

  def allows?(screen, at_least = 'view')
    Catalog.rank(level(screen)) >= Catalog.rank(at_least)
  end

  def screens
    Catalog::KEYS.index_with { |key| level(key) }
  end

  # técnico: o perfil é só telefone (abre direto na tela do técnico)
  def technician?
    !administrator? && profile.present? && (profile.kind == 'technician' || profile.technician?)
  end

  def kind
    return 'administrator' if administrator?

    technician? ? 'technician' : 'agent'
  end

  # tela inicial: técnico no telefone; sem conversas, a primeira tela liberada
  def home
    return 'phone' if technician?
    return 'conversations' if allows?('conversations')

    %w[crm teams voice_panel phone contacts].find { |screen| allows?(screen, screen == 'phone' ? 'use' : 'view') } || 'phone'
  end

  def admin_only_screens
    @admin_only_screens ||= Array(@account.internal_attributes.to_h[Outsider::Access::ADMIN_ONLY_KEY]) & Catalog::KEYS
  end

  def as_json(*)
    { kind: kind, home: home, screens: screens, locked: admin_only_screens,
      profile: profile && { id: profile.id, name: profile.name, kind: profile.kind } }
  end
end
