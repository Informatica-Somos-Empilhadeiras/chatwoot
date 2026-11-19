# OUTSIDER: busca de produtos do ERP (Outsider::Erp::Catalog) para vincular a um item da proposta, assim o item carrega
# o CodigoProduto real e os impostos do orçamento saem certos. Só leitura, escopada numa unidade da Somos.
class Api::V1::Accounts::Outsider::Erp::CatalogController < Api::V1::Accounts::Outsider::Erp::BaseController
  before_action :ensure_erp_use

  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }

  def index
    render json: { products: catalog.search(params.require(:company), params[:q]) }
  end

  private

  def catalog
    @catalog ||= ::Outsider::Erp::Catalog.new(Current.account)
  end

  def ensure_erp_use
    render json: { error: 'erp_forbidden' }, status: :forbidden unless can_use_erp?
  end
end
