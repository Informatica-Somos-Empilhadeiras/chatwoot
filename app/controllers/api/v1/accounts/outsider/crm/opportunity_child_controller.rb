# OUTSIDER: base das rotas de uma oportunidade (tarefas, linha do tempo e auditoria). Só passa
# quem enxerga a oportunidade: membros da unidade dela e administradores.
class Api::V1::Accounts::Outsider::Crm::OpportunityChildController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :fetch_opportunity

  private

  def fetch_opportunity
    @opportunity = crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity)).find(params[:opportunity_id])
  end

  def ensure_can_edit_opportunity
    render_forbidden unless crm_access.edit_opportunity?(@opportunity)
  end
end
