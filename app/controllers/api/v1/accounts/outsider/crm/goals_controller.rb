# OUTSIDER: metas mensais por unidade e por vendedor (Outsider::Crm::Goals). Só administradores.
class Api::V1::Accounts::Outsider::Crm::GoalsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin

  rescue_from ::Outsider::Crm::MonthlyConfig::Invalid do |error|
    render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity
  end

  def show
    render json: goals.for_month(month).merge('people' => crm_people)
  end

  def update
    render json: goals.update(params[:month].to_s, units: hash_param(:units), users: hash_param(:users)).merge('people' => crm_people)
  end

  private

  def goals
    ::Outsider::Crm::Goals.new(Current.account)
  end

  def month
    ::Outsider::Crm::MonthlyConfig.month(params[:month])
  end

  def hash_param(name)
    params[name].respond_to?(:to_unsafe_h) ? params[name].to_unsafe_h.transform_values(&:to_s) : {}
  end
end
