# OUTSIDER: quais ligações cada pessoa vê no CRM (Entrega 22). Administrador e gestor veem todas; o vendedor
# vê as dele e as perdidas que são para ele retornar: do cliente dele (negócio aberto em que é o dono) ou
# do número do estado dele.
class Outsider::Voice::CallAccess
  def initialize(access, settings)
    @access = access
    @settings = settings
    @user_id = access.account_user.user_id
  end

  def scope(calls)
    return calls if @access.manager?

    state = @settings.agent_for(@user_id)&.dig('state')
    my_deals = Outsider::Crm::Opportunity.where(account_id: @access.account_user.account_id, owner_id: @user_id).select(:id)
    missed = calls.missed.where(opportunity_id: my_deals)
    missed = missed.or(calls.missed.where(state_code: state)) if state
    calls.where(user_id: @user_id).or(missed)
  end
end
