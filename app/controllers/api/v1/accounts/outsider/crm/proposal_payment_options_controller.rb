# OUTSIDER: opções de condição de pagamento para o editor de propostas (todos do CRM). Quem muda a lista é
# o administrador, em Configurações > Propostas > Pagamento (proposal_settings#general).
class Api::V1::Accounts::Outsider::Crm::ProposalPaymentOptionsController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  def show
    render json: { payload: ::Outsider::Crm::ProposalConfig.new(Current.account).payment_options }
  end
end
