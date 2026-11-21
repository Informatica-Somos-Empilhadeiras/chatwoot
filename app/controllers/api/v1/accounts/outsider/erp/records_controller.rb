# OUTSIDER: listas e detalhe da seção ERP (orçamentos, OS, pedidos de venda e notas fiscais) lidos direto do banco do ERP,
# com todo o histórico (Outsider::Erp::Records). kind: quotes | orders | sales | invoices (NF-e) | service_invoices
# (NFS-e). Só leitura; a edição continua nas rotas próprias
# (orçamento do chat em BudgetsController, OS em ServiceOrdersController). Cada aba segue a linha dela no perfil de acesso.
class Api::V1::Accounts::Outsider::Erp::RecordsController < Api::V1::Accounts::Outsider::Erp::BaseController
  rescue_from(::Outsider::Erp::Records::Detail::NotFound, ::Outsider::Erp::QuoteReport::NotFound) do
    render json: { error: 'not_found' }, status: :not_found
  end
  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  rescue_from(::Outsider::Erp::NextcloudInvoices::NotFound) { render json: { error: 'invoice_not_in_nextcloud' }, status: :not_found }
  rescue_from(::Outsider::Erp::NextcloudInvoices::Error) do |error|
    render json: { error: 'nextcloud_unavailable', message: error.message }, status: :service_unavailable
  end
  before_action :ensure_kind

  # q, view, company, person (código do vendedor/técnico), from, to (AAAA-MM-DD), page, per, sort, direction;
  # contact_id (os clientes do ERP do contato) ou client=empresa:código
  def index
    lister = ::Outsider::Erp::Records::Lister.new(Current.account, params[:kind], user: Current.user)
    render json: lister.page(list_params.merge(clients: clients)).merge(clients_scope)
  end

  def show
    render json: ::Outsider::Erp::Records::Detail.new(Current.account, params[:kind]).build(params[:company].to_s, params[:number])
  end

  # PDF do orçamento no modelo do relatório do Mais Prático, lido direto do ERP (não cria registro no chat: serve a quem só vê)
  def pdf
    company = params[:company].to_s
    raise ArgumentError, 'company' unless settings.companies.include?(company)

    document = ::Outsider::Erp::QuotePdf.new(::Outsider::Erp::QuoteReport.new(Current.account).build(company, params[:number].to_i))
    send_data document.render, filename: document.filename, type: 'application/pdf', disposition: 'inline'
  end

  # NF-e e NFS-e: o PDF oficial da nota espelhado do Nextcloud (achado pelo número, pedido, cliente e CFOP), para ver e baixar
  def document
    raise ::Outsider::Erp::NextcloudInvoices::NotFound unless settings.nextcloud_enabled?

    file = ::Outsider::Erp::NextcloudInvoices.new(Current.account).fetch(params[:company].to_s, params[:number], params[:kind])
    send_data file['content'], filename: file['filename'], type: 'application/pdf', disposition: 'inline'
  end

  private

  LIST_PARAMS = %i[q view company person from to page per sort direction].freeze

  def list_params = LIST_PARAMS.index_with { |key| params[key] }

  SCREENS = {
    'quotes' => 'erp_quotes', 'orders' => 'erp_orders', 'sales' => 'erp_sales', 'invoices' => 'erp_invoices', 'service_invoices' => 'erp_invoices'
  }.freeze

  # a lista pede a aba ligada nas Configurações; o detalhe (aberto também pela corrente, no painel) só o tipo válido.
  # Os dois pedem a linha da aba aberta no perfil de acesso.
  LIST_SETTINGS = { 'quotes' => :quotes_enabled?, 'orders' => :orders_enabled? }.freeze

  def ensure_kind
    setting = LIST_SETTINGS[params[:kind]]
    return render json: { error: 'kind_disabled' }, status: :forbidden if action_name == 'index' && setting && !settings.public_send(setting)

    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?(SCREENS.fetch(params[:kind]))
  end

  def clients
    return ::Outsider::Erp::ContactLink.new(contact).links if params[:contact_id].present?
    return [params[:client].to_s.split(':', 2)] if params[:client].present?

    nil
  end

  # a tela mostra "Clientes do contato X" quando a lista veio filtrada por um contato
  def clients_scope
    return {} if params[:contact_id].blank?

    { contact: { id: contact.id, name: contact.name, clients: ::Outsider::Erp::ContactLink.new(contact).links } }
  end
end
