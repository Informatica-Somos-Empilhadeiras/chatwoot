# OUTSIDER: aba Relatórios do CRM. Cada um vê os números das unidades que acompanha (as mesmas do
# Kanban); nas unidades em que é só vendedor, só os dos próprios negócios. Unidade, responsável e
# período valem para tudo; o funil é de um pipeline por vez
# (pipeline_id, ou o primeiro pipeline ativo das unidades filtradas).
class Api::V1::Accounts::Outsider::Crm::ReportsController < Api::V1::Accounts::Outsider::Crm::BaseController
  def show
    period = ::Outsider::Crm::ReportPeriod.new(params[:period])
    report = ::Outsider::Crm::Report.new(filtered, period: period).to_h
    pipeline = selected_pipeline
    report[:funnel] = pipeline && ::Outsider::Crm::StageReport.new(filtered, pipeline: pipeline, period: period).to_h
    render json: report
  end

  private

  def filtered
    scope = crm_access.metrics(crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity)))
    scope = scope.where(business_unit_id: params[:business_unit_id]) if params[:business_unit_id].present?
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope
  end

  def selected_pipeline
    pipelines = crm_scope(::Outsider::Crm::Pipeline).where(business_unit_id: crm_access.visible_unit_ids).ordered
    pipelines = pipelines.where(business_unit_id: params[:business_unit_id]) if params[:business_unit_id].present?
    (params[:pipeline_id].present? && pipelines.find_by(id: params[:pipeline_id])) || pipelines.active.first
  end
end
