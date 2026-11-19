# OUTSIDER: a lista de clientes do ERP (Outsider::Erp::Customers) para vincular a um contato: abre pronta, com os parecidos
# com o contato (telefone ou nome) no topo, e filtra por nome, código ou CPF/CNPJ.
class Api::V1::Accounts::Outsider::Erp::CustomersController < Api::V1::Accounts::Outsider::Erp::BaseController
  def index
    customer_contact = Current.account.contacts.find(params[:contact_id]) if params[:contact_id].present?
    render json: { customers: ::Outsider::Erp::Customers.new(Current.account).list(params[:q], contact: customer_contact) }
  end
end
