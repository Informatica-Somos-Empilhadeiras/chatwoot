# OUTSIDER: vincula ou desvincula um contato de um cliente do ERP (empresa + código), ver Outsider::Erp::ContactLink
class Api::V1::Accounts::Outsider::Erp::ContactLinksController < Api::V1::Accounts::Outsider::Erp::BaseController
  rescue_from(::Outsider::Erp::ContactLink::Invalid) do |error|
    render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity
  end

  def create
    render json: { links: link.add(company: params.require(:company), code: params.require(:code), name: params[:name], settings: settings) }
  end

  def destroy
    render json: { links: link.remove(company: params.require(:company), code: params.require(:code)) }
  end

  private

  def link
    ::Outsider::Erp::ContactLink.new(contact)
  end
end
