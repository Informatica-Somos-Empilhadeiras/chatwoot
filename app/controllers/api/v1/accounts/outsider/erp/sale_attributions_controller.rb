# OUTSIDER: técnico e OS de um pedido de venda, informados no chat (Outsider::Erp::SaleAttributor). Ver pede a aba
# Pedidos do perfil; gravar e tirar pedem "Usa" nela. Nada é gravado no ERP.
class Api::V1::Accounts::Outsider::Erp::SaleAttributionsController < Api::V1::Accounts::Outsider::Erp::BaseController
  before_action :ensure_sales_view
  before_action :ensure_sales_use, only: %i[update destroy]

  rescue_from(::Outsider::Erp::SaleAttributor::NotFound) { render json: { error: 'not_found' }, status: :not_found }
  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  rescue_from(::Outsider::Erp::SaleAttributor::Invalid) do |error|
    render json: { error: 'attribution_invalid', reason: error.message }.merge(error.details), status: :unprocessable_entity
  end
  rescue_from(::Outsider::Erp::DiscountApprover::Refused) do |error|
    render json: { error: 'attribution_invalid', reason: error.message }, status: :unprocessable_entity
  end

  def show
    render json: attributor.show(company, number)
  end

  # GET com os[]: confere as OS digitadas antes de gravar
  def preview
    render json: attributor.preview(company, number, Array(params[:os]))
  end

  # lines: [{ os, parte }]; approval: { code, password } (senha comercial, quando alguma OS não bate com o pedido)
  def update
    lines = params.permit(lines: %i[os parte]).fetch(:lines, []).map(&:to_h)
    approval = params.fetch(:approval, {}).permit(:code, :password).to_h
    render json: attributor.save(company, number, lines, approval)
  end

  def destroy
    render json: { vinculo: attributor.clear(company, number) }
  end

  private

  def attributor = ::Outsider::Erp::SaleAttributor.new(Current.account_user)
  def company = params.require(:company).to_s
  def number = Integer(params.require(:number).to_s, 10)

  def ensure_sales_view
    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?('erp_sales')
  end

  def ensure_sales_use
    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?('erp_sales', 'use')
  end
end
