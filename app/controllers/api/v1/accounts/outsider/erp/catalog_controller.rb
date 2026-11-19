# OUTSIDER: lista de peças e serviços do ERP (Outsider::Erp::Catalog) para o orçamento de peças e serviços: abre pronta e
# filtra por código ou nome; "technical" traz a descrição técnica de um produto. Só leitura, escopada numa unidade da Somos.
class Api::V1::Accounts::Outsider::Erp::CatalogController < Api::V1::Accounts::Outsider::Erp::BaseController
  before_action :ensure_erp_use

  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }

  def index
    render json: { products: catalog.search(params.require(:company), params[:q]) }
  end

  def technical
    render json: { technical: catalog.technical(params.require(:company), Integer(params.require(:code).to_s)) }
  end

  private

  def catalog
    @catalog ||= ::Outsider::Erp::Catalog.new(Current.account)
  end

  def ensure_erp_use
    render json: { error: 'erp_forbidden' }, status: :forbidden unless can_use_erp?
  end
end
