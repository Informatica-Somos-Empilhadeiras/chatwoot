# OUTSIDER: unidades comerciais do grupo. Membros veem as suas; só administradores alteram.
class Api::V1::Accounts::Outsider::Crm::BusinessUnitsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin, except: [:index, :show]
  before_action :fetch_unit, only: [:show, :update, :destroy]

  def index
    units = crm_scope(::Outsider::Crm::BusinessUnit).where(id: crm_access.visible_unit_ids).ordered
    render json: units.map { |unit| unit_json(unit) }
  end

  def show
    render json: unit_json(@unit, members: true)
  end

  def create
    unit = crm_scope(::Outsider::Crm::BusinessUnit).create!(unit_params)
    render json: unit_json(unit, members: true), status: :created
  end

  def update
    @unit.update!(unit_params)
    render json: unit_json(@unit, members: true)
  end

  # Unidade com pipeline ou oportunidade não é apagada: desative (active: false)
  def destroy
    remover.unit(@unit)
    head :no_content
  end

  private

  def fetch_unit
    @unit = crm_scope(::Outsider::Crm::BusinessUnit).where(id: crm_access.visible_unit_ids).find(params[:id])
  end

  def unit_params
    params.require(:business_unit).permit(:name, :description, :active, :position)
  end

  def unit_json(unit, members: false)
    json = unit.slice(:id, :name, :description, :active, :position)
    return json unless members

    json.merge(members: unit.members.includes(:user).map do |member|
      { id: member.id, user_id: member.user_id, name: member.user.name, email: member.user.email, role: member.role }
    end)
  end
end
