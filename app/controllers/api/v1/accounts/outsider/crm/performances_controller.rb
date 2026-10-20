# OUTSIDER: aba Metas do CRM (Outsider::Crm::Performance): metas, vendido e comissão do mês.
class Api::V1::Accounts::Outsider::Crm::PerformancesController < Api::V1::Accounts::Outsider::Crm::BaseController
  def show
    month = ::Outsider::Crm::MonthlyConfig.month(params[:month])
    render json: ::Outsider::Crm::Performance.new(crm_access, month).to_h
  end
end
