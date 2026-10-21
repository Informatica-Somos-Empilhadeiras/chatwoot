# OUTSIDER: rodízio de vendedores por unidade, usado pelo repasse em sequência (LostChain) quando a
# conta escolhe "rodízio". Guarda em accounts.internal_attributes quem recebeu por último em cada
# unidade e passa para o próximo, em ordem de id. Sem vendedor na unidade, roda entre os gestores;
# sem ninguém, o negócio fica sem responsável (e a unidade toda recebe o aviso). Quem saiu da conta ou
# está com o CRM desligado (Outsider::Crm::Switch) fica fora da vez.
class Outsider::Crm::Rotation
  KEY = 'outsider_crm_rotation'.freeze

  def initialize(account)
    @account = account
  end

  # Chame dentro da transação do encaminhamento: se ele for recusado, a vez não avança
  def next_user_id!(unit_id)
    candidates = candidate_ids(unit_id)
    return if candidates.empty?

    @account.with_lock do
      pointers = @account.internal_attributes.fetch(KEY, {})
      last = pointers[unit_id.to_s].to_i
      chosen = candidates.find { |id| id > last } || candidates.first
      merged = @account.internal_attributes.merge(KEY => pointers.merge(unit_id.to_s => chosen))
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: merged) # rubocop:disable Rails/SkipsModelValidations
      chosen
    end
  end

  def candidate_ids(unit_id)
    members = Outsider::Crm::BusinessUnitMember.where(account_id: @account.id, business_unit_id: unit_id)
                                               .where(user_id: AccountUser.where(account_id: @account.id).select(:user_id))
                                               .where.not(user_id: Outsider::Crm::Switch.new(@account).disabled_agent_ids)
    sellers = members.where(role: :seller).pluck(:user_id).sort
    sellers.presence || members.pluck(:user_id).sort
  end
end
