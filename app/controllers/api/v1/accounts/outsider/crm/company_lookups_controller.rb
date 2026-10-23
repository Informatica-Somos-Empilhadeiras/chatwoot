# OUTSIDER: dados da empresa do cliente pelo CNPJ, para o editor de propostas (Outsider::Crm::CompanyLookup).
# Devolve só os campos da proposta; quem tem o CRM consulta.
class Api::V1::Accounts::Outsider::Crm::CompanyLookupsController < Api::V1::Accounts::Outsider::Crm::BaseController
  rescue_from(::Outsider::Crm::CompanyLookup::Invalid) { render json: { error: 'invalid_document' }, status: :unprocessable_entity }
  rescue_from(::Outsider::Crm::CompanyLookup::NotFound) { render json: { error: 'not_found' }, status: :not_found }
  rescue_from(::Outsider::Crm::CompanyLookup::Unavailable) { render json: { error: 'unavailable' }, status: :service_unavailable }

  def show
    render json: ::Outsider::Crm::CompanyLookup.new(params[:document]).perform
  end
end
