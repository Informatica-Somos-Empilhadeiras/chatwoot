# OUTSIDER: agentes de cada unidade e seu papel (seller ou manager). Só administradores alteram.
class Api::V1::Accounts::Outsider::Crm::BusinessUnitMembersController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin
  before_action :fetch_unit

  def create
    member = @unit.members.create!(account: Current.account, user_id: params.require(:user_id), role: role_param || :seller)
    render json: member_json(member), status: :created
  rescue ArgumentError
    render json: { error: 'invalid_role' }, status: :unprocessable_entity
  end

  def update
    member = @unit.members.find(params[:id])
    member.update!(role: role_param)
    render json: member_json(member)
  rescue ArgumentError
    render json: { error: 'invalid_role' }, status: :unprocessable_entity
  end

  def destroy
    @unit.members.find(params[:id]).destroy!
    head :no_content
  end

  private

  def fetch_unit
    @unit = crm_scope(::Outsider::Crm::BusinessUnit).find(params[:business_unit_id])
  end

  def role_param
    params[:role].presence
  end

  def member_json(member)
    { id: member.id, user_id: member.user_id, name: member.user.name, email: member.user.email, role: member.role }
  end
end
