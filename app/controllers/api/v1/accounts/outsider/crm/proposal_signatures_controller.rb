# OUTSIDER: a própria assinatura das propostas (cargo e telefone), que cada pessoa do CRM ajusta na proposta
class Api::V1::Accounts::Outsider::Crm::ProposalSignaturesController < Api::V1::Accounts::Outsider::Crm::BaseController
  def show
    render json: proposal_config.signature(Current.user.id)
  end

  def update
    proposal_config.update_signature(Current.user.id, params.require(:signature).permit(*::Outsider::Crm::ProposalConfig::SIGNATURE_KEYS))
    render json: proposal_config.signature(Current.user.id)
  end

  private

  def proposal_config
    ::Outsider::Crm::ProposalConfig.new(Current.account)
  end
end
