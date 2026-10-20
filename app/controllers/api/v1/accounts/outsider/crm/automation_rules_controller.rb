# OUTSIDER: regras de automação "quando acontecer X, faça Y" (Outsider::Crm::AutomationRules).
# Só administradores do CRM veem e alteram.
class Api::V1::Accounts::Outsider::Crm::AutomationRulesController < Api::V1::Accounts::Outsider::Crm::BaseController
  CONDITIONS = %i[business_unit_id pipeline_id stage_id min_value_cents].freeze
  ACTION_FIELDS = %i[type title kind description due_in_hours assignee user_id label body].freeze

  before_action :ensure_crm_admin

  rescue_from ::Outsider::Crm::AutomationRules::Invalid do |error|
    render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity
  end

  def index
    render json: rules.all
  end

  def create
    render json: rules.create(rule_params), status: :created
  end

  def update
    render json: rules.update(params[:id], rule_params)
  end

  def destroy
    rules.destroy(params[:id])
    head :no_content
  end

  private

  def rules
    @rules ||= ::Outsider::Crm::AutomationRules.new(Current.account)
  end

  def rule_params
    params.require(:automation_rule).permit(:name, :active, :trigger, :wait_hours, conditions: CONDITIONS, actions: ACTION_FIELDS).to_h
  end
end
