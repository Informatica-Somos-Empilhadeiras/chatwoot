# OUTSIDER: as OS do ERP (espelho): as do contato, a busca, o quadro e a gravação de substatus/campos (Outsider::Erp::Writer)
class Api::V1::Accounts::Outsider::Erp::ServiceOrdersController < Api::V1::Accounts::Outsider::Erp::BaseController
  rescue_from(::Outsider::Erp::Writer::Disabled) { render json: { error: 'write_disabled' }, status: :forbidden }
  rescue_from(::Outsider::Erp::Writer::Invalid) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  before_action :ensure_orders_enabled, only: :board

  # contact_id: os vínculos do contato e as OS desses clientes; q: busca por número, cliente, máquina. Com as OS ocultas,
  # só os vínculos (o orçamento precisa deles). O cliente para vincular vem da lista de clientes (CustomersController).
  def index
    render json: params[:contact_id].present? ? contact_orders : search_orders
  end

  def board
    data = orders.board(group_by: params[:group_by], company: params[:company], technician: params[:technician], query: params[:q])
    render json: orders.meta.merge(data).merge(options: data[:companies].index_with { |company| orders.substatus_options(company) })
  end

  def substatus
    render json: { order: writer.substatus(company: params.require(:company), code: params.require(:code), value: params.require(:value),
                                           conversation: conversation) }
  end

  def field
    render json: { order: writer.field(company: params.require(:company), code: params.require(:code), field: params.require(:field),
                                       value: params[:value].to_s, conversation: conversation) }
  end

  def status
    render json: { order: writer.status(company: params.require(:company), code: params.require(:code), value: params.require(:value),
                                        conversation: conversation) }
  end

  def attendance_type
    render json: { order: writer.attendance_type(company: params.require(:company), code: params.require(:code), value: params.require(:value),
                                                 conversation: conversation) }
  end

  def technician
    order = writer.technician(company: params.require(:company), code: params.require(:code), tecnico_id: params.require(:tecnico_id),
                              tecnico_name: params[:tecnico_name], conversation: conversation)
    render json: { order: order }
  end

  private

  def contact_orders
    links = ::Outsider::Erp::ContactLink.new(contact).links
    data = { links: links, orders: [], options: {} }
    return data unless settings.orders_enabled? && links.any?

    orders.meta.merge(data).merge(orders: orders.for_clients(links), options: options_for(links))
  end

  def search_orders
    return { orders: [], options: {} } unless settings.orders_enabled?

    found = orders.search(params[:q])
    orders.meta.merge(orders: found, options: options_for(found.map { |order| { 'empresa' => order['Empresa'] } }))
  end

  def writer
    raise ::Outsider::Erp::Writer::Disabled unless can_edit?

    ::Outsider::Erp::Writer.new(account: Current.account, user: Current.user)
  end

  # substatus que dá para escolher, por empresa
  def options_for(rows)
    rows.filter_map { |row| row['empresa'] }.uniq.index_with { |company| orders.substatus_options(company) }
  end

  def conversation
    return if params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    conversation
  end
end
