# OUTSIDER: "Cadastrar cliente no ERP" (Outsider::Erp::ClientRegistrar): o pré-cadastro pela função do próprio Mais
# Prático. Só com a gravação de clientes ligada nas Configurações (desligada por padrão) e para quem "Usa" o Cadastro de
# clientes no perfil de acesso. A unidade é sempre uma das Configurações.
class Api::V1::Accounts::Outsider::Erp::ClientsController < Api::V1::Accounts::Outsider::Erp::BaseController
  FIELDS = %i[company documento nome apelido rg_ie telefone celular email cep endereco numero bairro cidade uf referencia vendedor
              contato_nome contato_telefone contato_email observacoes copiar_endereco].freeze

  before_action :ensure_client_write

  rescue_from(::Outsider::Erp::ClientRegistrar::Invalid) do |error|
    render json: { error: 'invalid', reason: error.message, fields: error.fields }, status: :unprocessable_entity
  end
  rescue_from(::Outsider::Crm::CompanyLookup::Invalid) { render json: { error: 'invalid_document' }, status: :unprocessable_entity }
  rescue_from(::Outsider::Crm::CompanyLookup::NotFound) { render json: { error: 'not_found' }, status: :not_found }
  rescue_from(::Outsider::Crm::CompanyLookup::Unavailable) { render json: { error: 'unavailable' }, status: :service_unavailable }

  # vendedores da unidade e o vendedor do agente (o mesmo que o orçamento pré-preenche)
  def options
    company = params.require(:company).to_s
    return render(json: { error: 'invalid', reason: 'empresa' }, status: :unprocessable_entity) unless settings.companies.include?(company)

    render json: { sellers: sellers(company), seller: seller_code }
  end

  # já existe um cliente com este CPF/CNPJ na unidade? (a tela avisa antes de gravar)
  def lookup
    render json: { customer: registrar.existing(params.require(:company), params.require(:documento)) }
  end

  # dados da empresa pelo CNPJ para preencher o cadastro (a mesma consulta das propostas: Outsider::Crm::CompanyLookup)
  def company
    render json: ::Outsider::Crm::CompanyLookup.new(params.require(:documento)).perform
  end

  def create
    customer_contact = Current.account.contacts.find(params[:contact_id]) if params[:contact_id].present?
    render json: { customer: registrar.call(params.require(:client).permit(*FIELDS).to_h, contact: customer_contact) }
  end

  private

  def registrar
    @registrar ||= ::Outsider::Erp::ClientRegistrar.new(Current.account, user: Current.user)
  end

  def ensure_client_write
    return if can_register_client?

    render json: { error: settings.client_write_enabled? ? 'no_permission' : 'client_write_disabled' }, status: :forbidden
  end

  def sellers(company)
    ::Outsider::Erp::Sellers.new(Current.account).list(company)
  rescue ::Outsider::Erp::Client::Error => e
    Rails.logger.warn("[Outsider::Erp] vendedores do cadastro de cliente: #{e.message}")
    []
  end

  def seller_code
    code = Integer(settings.data['user_erp_ids'].to_h[Current.user.id.to_s].to_s, exception: false)
    code if code&.positive?
  end
end
