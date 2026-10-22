# OUTSIDER: seção "Propostas" da aba Relatórios (Entrega 18). Só as propostas que a pessoa pode ver
# (Outsider::Crm::ProposalAccess), com os mesmos filtros de unidade, responsável e período da aba.
class Api::V1::Accounts::Outsider::Crm::ProposalReportsController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  def show
    period = ::Outsider::Crm::ReportPeriod.new(params[:period])
    render json: ::Outsider::Crm::ProposalReport.new(filtered, period: period).to_h
  end

  private

  def filtered
    scope = proposal_access.proposals
    scope = unit_filter(scope, params[:business_unit_id]) if params[:business_unit_id].present?
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope
  end

  # Proposta sem unidade escolhida vale pela unidade do negócio ligado
  def unit_filter(scope, unit_id)
    deals = ::Outsider::Crm::Opportunity.where(account_id: Current.account.id, business_unit_id: unit_id).select(:id)
    scope.where(business_unit_id: unit_id).or(scope.where(business_unit_id: nil, opportunity_id: deals))
  end
end
