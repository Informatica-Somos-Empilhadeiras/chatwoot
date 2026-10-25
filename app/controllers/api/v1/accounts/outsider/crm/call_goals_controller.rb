# OUTSIDER: metas mensais de ligação por vendedor (Outsider::Crm::CallGoals). Só administradores.
class Api::V1::Accounts::Outsider::Crm::CallGoalsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin

  rescue_from ::Outsider::Crm::MonthlyConfig::Invalid do |error|
    render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity
  end

  def show
    render json: goals.for_month(month).merge('people' => people)
  end

  def update
    users = params[:users].respond_to?(:to_unsafe_h) ? params[:users].to_unsafe_h : {}
    render json: goals.update(params[:month].to_s, users: users).merge('people' => people)
  end

  private

  def goals
    ::Outsider::Crm::CallGoals.new(Current.account)
  end

  def month
    ::Outsider::Crm::MonthlyConfig.month(params[:month])
  end

  # quem tem ramal ligado na telefonia
  def people
    agents = ::Outsider::Voice::Settings.new(Current.account).enabled_agents
    User.where(id: agents.keys).order(:name).map do |user|
      { id: user.id, name: user.name, thumbnail: user.avatar_url, extension: agents[user.id]['extension'], state: agents[user.id]['state'] }
    end
  end
end
