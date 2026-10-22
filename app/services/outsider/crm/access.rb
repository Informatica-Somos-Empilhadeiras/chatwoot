# OUTSIDER: quem pode o quê no CRM. Antes de tudo o CRM precisa estar ligado na conta e para a pessoa
# (Outsider::Crm::Switch). Administradores podem tudo. Os demais só entram no CRM se
# forem membros de alguma unidade: seller vê as oportunidades da unidade e edita as suas,
# manager edita todas da unidade. Não depende de custom roles (recurso pago do Chatwoot).
#
# Nas unidades em que a pessoa é só vendedor, os indicadores (topo do Kanban, Relatórios, Metas)
# contam só os negócios dela. Com a opção "vendedor vê só os próprios negócios" ligada, a lista,
# o Kanban e a conversa também mostram só os dela e os que estão sem responsável. A tela principal
# (main_list) mostra ao vendedor os negócios em que é o responsável e os sem responsável das suas
# unidades (para pegar); gestor e administrador veem os das unidades que acompanham.
class Outsider::Crm::Access
  attr_reader :account_user

  def initialize(account_user)
    @account_user = account_user
  end

  def administrator?
    account_user.administrator?
  end

  def enabled?
    return @enabled if defined?(@enabled)

    @enabled = switch.enabled_for?(account_user) && (administrator? || memberships.any?)
  end

  # Por que a pessoa não entra no CRM: 'account' (desligado na conta), 'agent' (desligado para ela pelo
  # administrador da conta) ou 'no_unit' (não está em nenhuma unidade)
  def disabled_reason
    return if enabled?
    return 'account' unless switch.account_enabled?
    return 'agent' unless switch.agent_enabled?(account_user)

    'no_unit'
  end

  def visible_unit_ids
    administrator? ? units.pluck(:id) : memberships.map(&:business_unit_id)
  end

  def manager_unit_ids
    memberships.select(&:manager?).map(&:business_unit_id)
  end

  def member_unit_ids
    memberships.map(&:business_unit_id)
  end

  # Unidades em que a pessoa vê só o que é seu (vendedor, sem ser gestor nem administrador)
  def seller_unit_ids
    administrator? ? [] : member_unit_ids - manager_unit_ids
  end

  # Unidades em que a pessoa acompanha todos os números (administrador ou gestor)
  def full_unit_ids
    administrator? ? visible_unit_ids : manager_unit_ids
  end

  def manager?
    administrator? || manager_unit_ids.any?
  end

  def member_of?(unit_id)
    administrator? || memberships.any? { |membership| membership.business_unit_id == unit_id }
  end

  def manage_unit?(unit_id)
    administrator? || manager_unit_ids.include?(unit_id)
  end

  def opportunities(scope = Outsider::Crm::Opportunity.where(account_id: account_user.account_id))
    return scope if administrator?

    scope = scope.where(business_unit_id: visible_unit_ids)
    own_deals_only? ? own(scope, unowned: true) : scope
  end

  # Tela principal do CRM (lista, Kanban, indicadores do topo e CSV): o vendedor vê os negócios em
  # que é o responsável e os sem responsável das unidades dele (a fila para pegar); o gestor vê
  # também todos os das unidades que gerencia e o administrador vê todos. Quem vê os dos outros
  # escolhe pelo filtro de responsável.
  def all_deals?
    manager?
  end

  def main_list(scope)
    return scope if administrator?

    scope.where('outsider_crm_opportunities.business_unit_id IN (:managed) OR outsider_crm_opportunities.owner_id = :user OR ' \
                '(outsider_crm_opportunities.owner_id IS NULL AND outsider_crm_opportunities.business_unit_id IN (:member))',
                managed: manager_unit_ids.presence || [0], member: member_unit_ids.presence || [0], user: account_user.user_id)
  end

  # Pegar para si um negócio aberto sem responsável: qualquer membro da unidade (e o administrador)
  def claim_opportunity?(opportunity)
    opportunity.open? && opportunity.owner_id.nil? && member_of?(opportunity.business_unit_id)
  end

  # Base dos indicadores: nas unidades em que é só vendedor, só os negócios dele
  def metrics(scope)
    own(scope, unowned: false)
  end

  def view_opportunity?(opportunity)
    return false unless member_of?(opportunity.business_unit_id)
    return true unless own_deals_only? && seller_unit_ids.include?(opportunity.business_unit_id)

    [nil, account_user.user_id].include?(opportunity.owner_id)
  end

  # Negócio encaminhado (ou perdido e repassado) não muda mais, nem pelo administrador: a continuação
  # está no destino
  # Apagar negócio: administrador e gestor da unidade (vendedor não apaga, nem os próprios)
  def delete_opportunity?(opportunity)
    manage_unit?(opportunity.business_unit_id)
  end

  def edit_opportunity?(opportunity)
    return false if opportunity.handed_off?
    return true if manage_unit?(opportunity.business_unit_id)

    member_of?(opportunity.business_unit_id) && opportunity.owner_id == account_user.user_id
  end

  # Encaminha quem edita o negócio, enquanto ele está aberto
  def forward_opportunity?(opportunity)
    opportunity.open? && edit_opportunity?(opportunity)
  end

  # Quem edita o negócio mexe em todas as tarefas dele; o responsável pela tarefa pode
  # concluir e adiar a sua mesmo sem editar o negócio. No negócio que saiu para outra unidade, nada
  # muda (nem reabrir tarefa concluída no envio)
  def complete_task?(task)
    return false if task.opportunity.handed_off?

    edit_opportunity?(task.opportunity) || task.assignee_id == account_user.user_id
  end

  # Só notas se apagam: quem escreveu, o gestor da unidade ou o administrador
  def delete_activity?(activity)
    return false unless activity.note? && !activity.opportunity.handed_off?

    activity.user_id == account_user.user_id || manage_unit?(activity.opportunity.business_unit_id)
  end

  # Pode ser responsável por tarefa ou negócio da unidade: membros e administradores da conta, menos os
  # agentes com o CRM desligado (crm_only: false inclui esses, para validar regras já salvas)
  def assignable_user_ids(unit_id)
    self.class.assignable_user_ids(account_user.account_id, unit_id)
  end

  def self.assignable_user_ids(account_id, unit_id, crm_only: true)
    admins = AccountUser.where(account_id: account_id, role: :administrator).pluck(:user_id)
    members = Outsider::Crm::BusinessUnitMember.where(account_id: account_id, business_unit_id: unit_id).pluck(:user_id)
    ids = (admins + members).uniq
    crm_only ? Outsider::Crm::Switch.new(Account.find(account_id)).reject_disabled(ids) : ids
  end

  def as_json(*)
    return { enabled: false, administrator: administrator?, reason: disabled_reason, units: [] } unless enabled?

    {
      administrator: administrator?,
      manager: manager?,
      all_deals: all_deals?,
      enabled: true,
      units: visible_units.map { |unit| { id: unit.id, name: unit.name, role: role_in(unit.id) } },
      proposals: Outsider::Crm::ProposalAccess.new(account_user).as_json
    }
  end

  private

  def switch
    @switch ||= Outsider::Crm::Switch.new(account_user.account)
  end

  def units
    Outsider::Crm::BusinessUnit.where(account_id: account_user.account_id)
  end

  def visible_units
    units.where(id: visible_unit_ids).active.ordered
  end

  def role_in(unit_id)
    return 'administrator' if administrator?

    memberships.find { |membership| membership.business_unit_id == unit_id }&.role
  end

  def own(scope, unowned:)
    units = seller_unit_ids
    return scope if units.empty?

    sql = 'outsider_crm_opportunities.business_unit_id NOT IN (:units) OR outsider_crm_opportunities.owner_id = :user'
    sql += ' OR outsider_crm_opportunities.owner_id IS NULL' if unowned
    scope.where(sql, units: units, user: account_user.user_id)
  end

  def own_deals_only?
    return @own_deals_only if defined?(@own_deals_only)

    @own_deals_only = Outsider::Crm::Settings.new(account_user.account)[:sellers_see_own_deals]
  end

  def memberships
    @memberships ||= Outsider::Crm::BusinessUnitMember.where(account_id: account_user.account_id, user_id: account_user.user_id).to_a
  end
end
