# OUTSIDER: listas e detalhe da seção ERP (orçamentos, OS e pedidos de venda) lidos direto do banco do ERP, com todo o
# histórico (Outsider::Erp::Records). kind: quotes | orders | sales. Só leitura; a edição continua nas rotas próprias
# (orçamento do chat em BudgetsController, OS em ServiceOrdersController). Cada aba segue a linha dela no perfil de acesso.
class Api::V1::Accounts::Outsider::Erp::RecordsController < Api::V1::Accounts::Outsider::Erp::BaseController
  rescue_from(::Outsider::Erp::Records::Detail::NotFound, ::Outsider::Erp::QuoteReport::NotFound) do
    render json: { error: 'not_found' }, status: :not_found
  end
  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
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

  private

  LIST_PARAMS = %i[q view company person from to page per sort direction].freeze

  def list_params = LIST_PARAMS.index_with { |key| params[key] }

  SCREENS = { 'quotes' => 'erp_quotes', 'orders' => 'erp_orders', 'sales' => 'erp_sales' }.freeze

  # a aba precisa estar ligada nas Configurações e aberta no perfil de acesso
  def ensure_kind
    allowed = case params[:kind]
              when 'quotes' then settings.quotes_enabled?
              when 'orders' then settings.orders_enabled?
              when 'sales' then true
              end
    return render json: { error: 'kind_disabled' }, status: :forbidden unless allowed

    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?(SCREENS[params[:kind]])
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
