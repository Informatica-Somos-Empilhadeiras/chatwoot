# OUTSIDER: os três perfis prontos de cada conta (Administrador, Agente e Técnico), criados na primeira vez que alguém
# abre Perfis de acesso ou que o acesso de uma pessoa é calculado. Agente é o padrão de quem é cadastrado como agente e
# Técnico o de quem é cadastrado como técnico; o administrador pode trocar o padrão para um perfil criado por ele.
class Outsider::Access::Defaults
  NAMES = { 'administrator' => 'Administrador', 'agent' => 'Agente', 'technician' => 'Técnico' }.freeze
  DESCRIPTIONS = {
    'administrator' => 'Tudo liberado. Vale para quem é administrador da conta.',
    'agent' => 'Atende conversas, CRM e telefone.',
    'technician' => 'Mecânicos internos e externos e colaboradores de outras unidades: só o telefone.'
  }.freeze
  DEFAULT_FOR = { 'agent' => 'agent', 'technician' => 'technician' }.freeze

  def initialize(account)
    @account = account
  end

  def ensure!
    existing = Outsider::AccessProfile.where(account_id: @account.id, kind: NAMES.keys).pluck(:kind)
    (NAMES.keys - existing).each { |kind| create(kind) }
    Outsider::AccessProfile.where(account_id: @account.id)
  end

  # o perfil que vale para quem não tem perfil escolhido: o padrão de agentes (ou o pronto Agente)
  def default_for(type)
    ensure!
    scope = Outsider::AccessProfile.where(account_id: @account.id)
    scope.find_by(default_for: type) || scope.find_by(kind: type == 'technician' ? 'technician' : 'agent')
  end

  private

  def create(kind)
    name = unique_name(NAMES[kind])
    Outsider::AccessProfile.create!(account_id: @account.id, kind: kind, name: name, description: DESCRIPTIONS[kind],
                                    default_for: default_slot(kind), permissions: Outsider::Access::Catalog.defaults(kind))
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # outro perfil já pode ser o padrão (escolhido pelo administrador): o pronto não toma o lugar dele
  def default_slot(kind)
    slot = DEFAULT_FOR[kind]
    return unless slot

    Outsider::AccessProfile.exists?(account_id: @account.id, default_for: slot) ? nil : slot
  end

  # um perfil criado com o mesmo nome (ex.: "Técnico") não impede o pronto de nascer
  def unique_name(name)
    taken = Outsider::AccessProfile.where(account_id: @account.id).pluck(:name).map(&:downcase)
    return name unless taken.include?(name.downcase)

    (2..50).map { |n| "#{name} (#{n})" }.find { |candidate| taken.exclude?(candidate.downcase) }
  end
end
