# OUTSIDER: o PDF do contrato e da ficha da máquina (Locação e máquinas), no modelo escolhido em ERP > Modelos de relatório
# ou no modelo pronto (Outsider::Erp::Prints::Document.contract / .machine), e o envio dele ao cliente por WhatsApp ou
# e-mail, como o relatório da OS (Outsider::Erp::DocumentSending). Ver pede "Vê" e enviar pede "Usa" na linha Locação e
# máquinas do perfil de acesso. Só lê o ERP.
class Api::V1::Accounts::Outsider::Erp::RentalDocumentsController < Api::V1::Accounts::Outsider::Erp::BaseController
  include ::Outsider::Erp::DocumentSending

  SCREEN = 'erp_rentals'.freeze
  KINDS = { 'contracts' => 'contract', 'machines' => 'machine' }.freeze

  rescue_from(::Outsider::Erp::Records::Detail::NotFound) { render json: { error: 'not_found' }, status: :not_found }
  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  before_action { forbid unless allows_screen?(SCREEN, sending? ? 'use' : 'view') }

  def pdf
    send_data document.render, filename: document.filename, type: 'application/pdf', disposition: 'inline'
  end

  # textos, contato e caixas para a tela de envio (a mesma do relatório da OS)
  def delivery
    report = { 'numero' => params[:number].to_i, 'cliente' => { 'nome' => client_name } }
    render json: delivery_payload(client_company, report, document.filename, prefix)
  end

  def contacts
    render json: { contacts: send_recipients.contacts(params[:q]) }
  end

  def deliver
    deliver_document(-> { { 'filename' => document.filename, 'content' => document.render } }, label)
    render json: { ok: true }
  end

  private

  def sending? = %w[delivery contacts deliver].include?(action_name)

  def forbid = render(json: { error: 'erp_forbidden' }, status: :forbidden)

  def kind = KINDS.fetch(params[:kind].to_s)

  def detail
    @detail ||= ::Outsider::Erp::Prints::Document.rental_detail(Current.account, kind, params[:company].to_s, params[:number].to_i)
  end

  def document = @document ||= ::Outsider::Erp::Prints::Document.rental(Current.account, kind, detail)

  # os textos das Configurações (contrato: contract_*, ficha: machine_*)
  def prefix = kind

  def label = kind == 'contract' ? "Contrato Nº #{params[:number].to_i}" : "Ficha da máquina #{params[:number].to_i}"

  # o cliente do documento: o do contrato; na ficha, o cliente com quem a máquina está (Rentals::MachineDetail)
  def holder
    return detail['cliente_atual'] if kind == 'machine'

    { 'banco' => detail['company'], 'codigo' => detail.dig('header', 'cliente_codigo').to_i, 'nome' => detail.dig('cliente', 'nome') }
  end

  def client_company = holder['banco']
  def client_name = holder['nome'].to_s

  # sem contato escolhido nem conversa, o vinculado ao cliente do documento (delivery_contact procura pelo client_code)
  def delivery_contact(company, source)
    params[:client_code] = holder['codigo'] if params[:client_code].blank?
    super
  end
end
