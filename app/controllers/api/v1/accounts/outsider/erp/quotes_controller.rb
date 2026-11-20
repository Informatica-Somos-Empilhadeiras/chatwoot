# OUTSIDER: orçamentos do ERP dos clientes vinculados ao contato (Outsider::Erp::Quotes, espelho do painel do ERP).
# 202 "loading" na primeira vez: a busca vai para o Sidekiq e a tela tenta de novo. Os orçamentos feitos no chat ficam
# no BudgetsController (módulo de orçamento de peças e serviços, separado da proposta comercial).
class Api::V1::Accounts::Outsider::Erp::QuotesController < Api::V1::Accounts::Outsider::Erp::BaseController
  def index
    return render json: { error: 'quotes_disabled' }, status: :forbidden unless settings.quotes_enabled?

    quotes = ::Outsider::Erp::Quotes.new(Current.account)
    render json: quotes.meta.merge(quotes: quotes.for_clients(::Outsider::Erp::ContactLink.new(contact).links))
  end

  # listagem global da secao ERP: paginada, com busca e filtros
  def list
    return render json: { error: 'quotes_disabled' }, status: :forbidden unless settings.quotes_enabled?

    quotes = ::Outsider::Erp::Quotes.new(Current.account)
    render json: quotes.meta.merge(quotes.facets).merge(
      quotes.page(page: params[:page], per: params[:per], query: params[:q], status: params[:status], company: params[:company])
    )
  end
end
