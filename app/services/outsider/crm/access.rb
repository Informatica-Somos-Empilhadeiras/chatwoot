# OUTSIDER: quem pode o quê no CRM. Administradores podem tudo. Os demais só entram no CRM se
# forem membros de alguma unidade: seller vê as oportunidades da unidade e edita as suas,
# manager edita todas da unidade. Não depende de custom roles (recurso pago do Chatwoot).
class Outsider::Crm::Access
  attr_reader :account_user

  def initialize(account_user)
    @account_user = account_user
  end

  def administrator?
    account_user.administrator?
  end

  def enabled?
    administrator? || memberships.any?
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

  def member_of?(unit_id)
    administrator? || memberships.any? { |membership| membership.business_unit_id == unit_id }
  end

  def manage_unit?(unit_id)
    administrator? || manager_unit_ids.include?(unit_id)
  end

  def opportunities(scope = Outsider::Crm::Opportunity.where(account_id: account_user.account_id))
    administrator? ? scope : scope.where(business_unit_id: visible_unit_ids)
  end

  def view_opportunity?(opportunity)
    member_of?(opportunity.business_unit_id)
  end

  # Negócio encaminhado não muda mais, nem pelo administrador: a continuação está no destino
  # Apagar negócio: administrador e gestor da unidade (vendedor não apaga, nem os próprios)
  def delete_opportunity?(opportunity)
    manage_unit?(opportunity.business_unit_id)
  end

  def edit_opportunity?(opportunity)
    return false if opportunity.forwarded?
    return true if manage_unit?(opportunity.business_unit_id)

    member_of?(opportunity.business_unit_id) && opportunity.owner_id == account_user.user_id
  end

  # Encaminha quem edita o negócio, enquanto ele está aberto
  def forward_opportunity?(opportunity)
    opportunity.open? && edit_opportunity?(opportunity)
  end

  # Quem edita o negócio mexe em todas as tarefas dele; o responsável pela tarefa pode
  # concluir e adiar a sua mesmo sem editar o negócio
  def complete_task?(task)
    edit_opportunity?(task.opportunity) || task.assignee_id == account_user.user_id
  end

  # Só notas se apagam: quem escreveu, o gestor da unidade ou o administrador
  def delete_activity?(activity)
    return false unless activity.note? && !activity.opportunity.forwarded?

    activity.user_id == account_user.user_id || manage_unit?(activity.opportunity.business_unit_id)
  end

  # Pode ser responsável por tarefa ou negócio da unidade: membros e administradores da conta
  def assignable_user_ids(unit_id)
    admins = AccountUser.where(account_id: account_user.account_id, role: :administrator).pluck(:user_id)
    members = Outsider::Crm::BusinessUnitMember.where(account_id: account_user.account_id, business_unit_id: unit_id).pluck(:user_id)
    (admins + members).uniq
  end

  def as_json(*)
    {
      administrator: administrator?,
      enabled: enabled?,
      units: visible_units.map { |unit| { id: unit.id, name: unit.name, role: role_in(unit.id) } }
    }
  end

  private

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

  def memberships
    @memberships ||= Outsider::Crm::BusinessUnitMember.where(account_id: account_user.account_id, user_id: account_user.user_id).to_a
  end
end
