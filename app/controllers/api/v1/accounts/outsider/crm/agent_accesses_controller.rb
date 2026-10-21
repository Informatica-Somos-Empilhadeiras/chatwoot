# OUTSIDER: CRM > Configurações > Acesso. O administrador da conta liga e desliga o CRM para cada agente
# (Outsider::Crm::Switch). Administradores sempre têm o CRM e não aparecem como desligáveis.
class Api::V1::Accounts::Outsider::Crm::AgentAccessesController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin

  def index
    account_users = Current.account.account_users.includes(user: { avatar_attachment: :blob })
                           .sort_by { |account_user| account_user.user.name.to_s.downcase }
    render json: { payload: account_users.map { |account_user| person(account_user) } }
  end

  def update
    account_user = Current.account.account_users.includes(:user).find_by(user_id: params[:id])
    return render json: { error: 'not_found' }, status: :not_found if account_user.nil?
    return render json: { error: 'administrator' }, status: :unprocessable_entity if account_user.administrator?
    return render json: { error: 'enabled_missing' }, status: :unprocessable_entity unless params.key?(:enabled)

    switch.update_agent(account_user.user_id, ActiveModel::Type::Boolean.new.cast(params[:enabled]) == true)
    render json: person(account_user)
  end

  private

  def switch
    @switch ||= ::Outsider::Crm::Switch.new(Current.account)
  end

  def person(account_user)
    user = account_user.user
    {
      id: user.id, name: user.name, email: user.email, thumbnail: user.avatar_url,
      administrator: account_user.administrator?, enabled: switch.agent_enabled?(account_user),
      units: unit_names.fetch(user.id, []), open_deals: open_deals.fetch(user.id, 0)
    }
  end

  def unit_names
    @unit_names ||= crm_scope(::Outsider::Crm::BusinessUnitMember).includes(:business_unit).group_by(&:user_id)
                                                                  .transform_values { |list| list.map { |member| member.business_unit.name }.sort }
  end

  # negócios abertos no nome de cada um: quem for desligado continua dono deles até alguém reatribuir
  def open_deals
    @open_deals ||= crm_scope(::Outsider::Crm::Opportunity).open.where.not(owner_id: nil).group(:owner_id).count
  end
end
