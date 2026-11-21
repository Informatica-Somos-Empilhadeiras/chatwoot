# OUTSIDER: as OS do ERP (espelho): as do contato, a busca, o quadro, o relatório com as fotos (PDF), o envio dele ao
# cliente por WhatsApp/e-mail (Outsider::Erp::ServiceOrderSender) e a gravação de substatus/campos (Outsider::Erp::Writer)
class Api::V1::Accounts::Outsider::Erp::ServiceOrdersController < Api::V1::Accounts::Outsider::Erp::BaseController
  rescue_from(::Outsider::Erp::Writer::Disabled) { render json: { error: 'write_disabled' }, status: :forbidden }
  rescue_from(::Outsider::Erp::Writer::Invalid) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  rescue_from(::Outsider::Erp::Writer::Locked) { |error| render json: { error: 'os_locked', status: error.message }, status: :forbidden }
  rescue_from(::Outsider::Erp::ServiceOrderReport::NotFound) { render json: { error: 'os_not_found' }, status: :not_found }
  rescue_from(::Outsider::Erp::Delivery::Blocked) do |error|
    render json: { error: 'send_blocked', reason: error.message }, status: :unprocessable_entity
  end
  before_action :ensure_orders_enabled, only: %i[board report delivery contacts deliver]
  before_action :ensure_send_access, only: %i[delivery contacts deliver]

  # contact_id: os vínculos do contato e as OS desses clientes; q: busca por número, cliente, máquina. Com as OS ocultas,
  # só os vínculos (o orçamento precisa deles). O cliente para vincular vem da lista de clientes (CustomersController).
  def index
    render json: params[:contact_id].present? ? contact_orders : search_orders
  end

  def board
    data = orders.board(group_by: params[:group_by], company: params[:company], technician: params[:technician], query: params[:q])
    render json: orders.meta.merge(data).merge(options: data[:companies].index_with { |company| orders.substatus_options(company) })
  end

  # relatório da OS com as fotos do checklist (PDF no modelo do kanban de KPI do Mais Prático), lido direto do ERP: serve ao
  # quadro e ao histórico (OS fora da janela do espelho). Como o PDF do orçamento, só confere a unidade; a OS o ERP confirma.
  def report
    company, code = report_target
    document = ::Outsider::Erp::ServiceOrderPdf.new(::Outsider::Erp::ServiceOrderReport.new(Current.account).build(company, code))
    send_data document.render, filename: document.filename, type: 'application/pdf', disposition: 'inline'
  end

  # envio do relatório ao cliente (como o do orçamento): textos das Configurações, nome do arquivo e para quem/por onde
  def delivery
    company, code = report_target
    report = ::Outsider::Erp::ServiceOrderReport.new(Current.account).summary(company, code)
    source = conversation
    contact = delivery_contact(company, source)
    render json: {
      texts: ::Outsider::Erp::BudgetTexts.new(settings, report, Current.user, prefix: 'os', contact_name: contact&.name).as_json,
      filename: ::Outsider::Erp::ServiceOrderPdf.new(report).filename,
      recipients: send_recipients.for_contact(contact, conversation_id: source&.id)
    }
  end

  # busca de outro contato para o WhatsApp
  def contacts
    render json: { contacts: send_recipients.contacts(params[:q]) }
  end

  def deliver
    company, code = report_target
    ::Outsider::Erp::ServiceOrderSender.new(Current.account_user).deliver(company, code, deliver_params, conversation: conversation)
    render json: { ok: true }
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

  # unidade das Configurações e número da OS; a OS em si o ERP confirma (relatório de OS antiga do histórico também vale)
  def report_target
    company = params.require(:company).to_s
    code = Integer(params.require(:code).to_s, exception: false)
    raise ::Outsider::Erp::ServiceOrderReport::NotFound unless code && settings.companies.include?(company)

    [company, code]
  end

  # o contato escolhido na tela, senão o da conversa de onde abriu, senão o vinculado ao cliente da OS
  def delivery_contact(company, source)
    return Current.account.contacts.find_by(id: params[:contact_id]) if params[:contact_id].present?
    return source.contact if source

    linked = ::Outsider::Erp::Records::ContactFinder.new(Current.account).for_clients([[company, params[:client_code]]]).values.first
    linked && Current.account.contacts.find_by(id: linked['contact_id'])
  end

  # enviar o relatório ao cliente pede "Usa" na aba Ordens de serviço do perfil (o do orçamento pede na de Orçamentos)
  def ensure_send_access
    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?('erp_orders', 'use')
  end

  def send_recipients
    @send_recipients ||= ::Outsider::Erp::BudgetRecipients.new(Current.account_user)
  end

  def deliver_params
    params.permit(:channel, :contact_id, :inbox_id, :subject, :message, to: [])
  end

  def conversation
    return if params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    conversation
  end
end
