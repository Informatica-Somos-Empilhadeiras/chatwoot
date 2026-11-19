# OUTSIDER: orçamentos do ERP dos clientes vinculados ao contato (Outsider::Erp::Quotes). 202 "loading" na primeira vez:
# a busca vai para o Sidekiq e a tela tenta de novo. create: gera no ERP o orçamento de uma proposta do CRM
# (Outsider::Erp::QuoteCreator), com a flag própria de escrita de orçamento ligada.
class Api::V1::Accounts::Outsider::Erp::QuotesController < Api::V1::Accounts::Outsider::Erp::BaseController
  rescue_from(::Outsider::Erp::QuoteCreator::Disabled) { render json: { error: 'quote_write_disabled' }, status: :forbidden }
  rescue_from(::Outsider::Erp::QuoteCreator::Invalid) do |error|
    render json: { error: 'quote_invalid', reason: error.message }, status: :unprocessable_entity
  end

  def index
    return render json: { error: 'quotes_disabled' }, status: :forbidden unless settings.quotes_enabled?

    quotes = ::Outsider::Erp::Quotes.new(Current.account)
    render json: quotes.meta.merge(quotes: quotes.for_clients(::Outsider::Erp::ContactLink.new(contact).links))
  end

  def create
    return render json: { error: 'quote_write_disabled' }, status: :forbidden unless can_create_quote?

    proposal = editable_proposal
    return render json: { error: 'proposal_forbidden' }, status: :forbidden unless proposal

    result = ::Outsider::Erp::QuoteCreator.new(account: Current.account, user: Current.user, proposal: proposal,
                                               company: params[:company]).call
    render json: { number: result.number, company: result.company, skipped: result.skipped, already: result.already }
  end

  private

  # só a proposta que a pessoa vê no CRM (senão 404) e pode editar (administrador, responsável ou quem criou)
  def editable_proposal
    access = ::Outsider::Crm::ProposalAccess.new(Current.account_user)
    proposal = access.proposals.find(params.require(:proposal_id))
    proposal if access.edit?(proposal)
  end
end
