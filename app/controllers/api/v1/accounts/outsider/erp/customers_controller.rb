# OUTSIDER: clientes do ERP (tirados das OS do espelho) pelo nome, para vincular a um contato
class Api::V1::Accounts::Outsider::Erp::CustomersController < Api::V1::Accounts::Outsider::Erp::BaseController
  def index
    render json: orders.meta.merge(customers: orders.customers(params[:q], limit: 20))
  end
end
