# OUTSIDER: Ordens de serviço > Configurações (só administradores): endereço da API, empresas, cache, escrita e campos.
# "Testar" busca as OS agora (descarta a cópia) e devolve só contagens e nomes de colunas.
class Api::V1::Accounts::Outsider::Erp::SettingsController < Api::V1::Accounts::Outsider::Erp::BaseController
  skip_before_action :ensure_erp_enabled
  before_action :ensure_erp_admin

  TEST_TIMEOUT = 12

  rescue_from ::Outsider::Erp::Settings::Invalid do |error|
    render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity
  end

  def show
    render json: payload
  end

  def update
    settings.update(params.require(:settings).to_unsafe_h)
    [orders, ::Outsider::Erp::Quotes.new(Current.account), ::Outsider::Erp::Customers.new(Current.account)].each { |source| source.snapshot.clear }
    render json: payload
  end

  # formas de pagamento do ERP para escolher a padrão do orçamento numa lista (errors: unidade que não deu para ler)
  def payment_terms
    terms = ::Outsider::Erp::PaymentTerms.new(Current.account)
    render json: { payment_terms: terms.list, errors: terms.errors }
  end

  def test
    return render json: { error: 'no_companies' }, status: :unprocessable_entity if settings.companies.empty?

    # abaixo dos 15 s do rack-timeout de produção: ERP lento vira "Net::ReadTimeout" na tela, não um erro 500
    list = ::Outsider::Erp::Client.new(settings).service_orders(read_timeout: TEST_TIMEOUT)
    render json: {
      orders: list.size, companies: list.filter_map { |item| item['Empresa'] }.tally,
      columns: list.first.to_h.keys, substatus: list.filter_map { |item| item['SubStatus'].presence }.uniq.sort
    }
  end

  private

  def payload
    {
      settings: settings.as_json,
      people: Current.account.users.order(:name).map { |user| { id: user.id, name: user.name, thumbnail: user.avatar_url } },
      # seletores do orçamento (gênero da operação e tipo de frete padrão)
      quote_lists: { generos: ::Outsider::Erp::BudgetForm::GENEROS_PERMITIDOS, fretes: ::Outsider::Erp::BudgetForm::FRETES }
    }
  end
end
