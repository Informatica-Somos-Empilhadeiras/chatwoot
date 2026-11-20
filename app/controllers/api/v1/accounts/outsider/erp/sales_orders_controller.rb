# OUTSIDER: pedidos de venda do ERP (so visualizacao, espelho). Listagem paginada com busca por numero ou cliente.
class Api::V1::Accounts::Outsider::Erp::SalesOrdersController < Api::V1::Accounts::Outsider::Erp::BaseController
  def index
    sales = ::Outsider::Erp::SalesOrders.new(Current.account)
    render json: sales.meta.merge(sales.page(page: params[:page], per: params[:per], query: params[:q]))
  end
end
