# OUTSIDER: orçamentos do ERP dos clientes vinculados ao contato (Outsider::Erp::Quotes). 202 "loading" na primeira vez:
# a busca vai para o Sidekiq e a tela tenta de novo.
class Api::V1::Accounts::Outsider::Erp::QuotesController < Api::V1::Accounts::Outsider::Erp::BaseController
  def index
    return render json: { error: 'quotes_disabled' }, status: :forbidden unless settings.quotes_enabled?

    quotes = ::Outsider::Erp::Quotes.new(Current.account)
    render json: quotes.meta.merge(quotes: quotes.for_clients(::Outsider::Erp::ContactLink.new(contact).links))
  end
end
