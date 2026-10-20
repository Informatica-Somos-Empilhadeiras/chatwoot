# OUTSIDER: percentuais de comissão (Outsider::Crm::Commission). Só administradores. A alteração
# vale a partir do mês atual.
class Api::V1::Accounts::Outsider::Crm::CommissionsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin

  rescue_from ::Outsider::Crm::MonthlyConfig::Invalid do |error|
    render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity
  end

  def show
    render json: commission.for_month(::Outsider::Crm::MonthlyConfig.current_month).merge('people' => crm_people)
  end

  def update
    rules = Array(params[:rules]).map { |rule| rule.permit(:user_id, :business_unit_id, :bp).to_h }
    render json: commission.update(general_bp: params[:general_bp], rules: rules).merge('people' => crm_people)
  end

  private

  def commission
    ::Outsider::Crm::Commission.new(Current.account)
  end
end
