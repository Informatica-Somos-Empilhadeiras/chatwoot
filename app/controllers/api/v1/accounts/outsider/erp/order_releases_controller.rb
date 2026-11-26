# OUTSIDER: "Liberar para separação" no painel da OS do ERP (Outsider::Erp::Orders::Releaser): manda a OS para a fila de
# conferência do estoque, como o "Libera Conferência" do Mais Prático. Exige a função ligada nas Configurações (na unidade
# liberada) e "Usa" na linha "Liberar OS para separação" do perfil de acesso. Responde com a conferência lida de novo.
# "show" é só a conferência (o painel relê enquanto o estoque confere), para quem vê a aba Ordens de serviço.
class Api::V1::Accounts::Outsider::Erp::OrderReleasesController < Api::V1::Accounts::Outsider::Erp::BaseController
  before_action :ensure_orders_enabled
  before_action :ensure_company

  rescue_from(::Outsider::Erp::Orders::Releaser::Invalid) do |error|
    render json: { error: 'invalid', reason: error.message }, status: :unprocessable_entity
  end
  rescue_from(::Outsider::Erp::Orders::Releaser::Disabled) { render json: { error: 'release_disabled' }, status: :forbidden }

  def show
    return render json: { error: 'forbidden' }, status: :forbidden unless allows_screen?('erp_orders')

    render json: { conference: conference }
  end

  def create
    return render json: { error: 'release_forbidden' }, status: :forbidden unless can_release_order?

    ::Outsider::Erp::Orders::Releaser.new(Current.account, user: Current.user).call(company, params[:number])
    render json: { conference: conference }
  end

  private

  def company = params[:company].to_s

  def ensure_company
    render json: { error: 'invalid', reason: 'company' }, status: :unprocessable_entity unless settings.companies.include?(company)
  end

  def conference
    client = ::Outsider::Erp::Client.new(settings)
    ::Outsider::Erp::Orders::Conference.new(Current.account, client: client).build(company, params[:number])
  end
end
