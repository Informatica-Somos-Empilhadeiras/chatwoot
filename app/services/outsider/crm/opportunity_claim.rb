# OUTSIDER: "Pegar" um negócio aberto sem responsável da unidade (chegou pelo repasse em sequência ou
# foi encaminhado sem responsável). Trava a linha do negócio: se duas pessoas clicam juntas, só a
# primeira fica com ele e a outra recebe "outra pessoa pegou antes". A troca de responsável entra na
# linha do tempo como sempre. Negócio que chegou por encaminhamento e está sem tarefa pendente ganha
# a tarefa "Contatar cliente" para quem pegou, com o mesmo prazo do encaminhamento.
class Outsider::Crm::OpportunityClaim
  def initialize(opportunity, access:, user:)
    @opportunity = opportunity
    @access = access
    @user = user
  end

  # true quando a pessoa ficou com o negócio
  def perform
    Outsider::Crm::Opportunity.transaction do
      @opportunity.lock!
      next false unless @access.claim_opportunity?(@opportunity)

      @opportunity.update!(owner_id: @user.id)
      create_contact_task
      true
    end
  end

  private

  def create_contact_task
    origin = @opportunity.forwarded_from
    return if origin.nil? || @opportunity.tasks.pending.exists?

    @opportunity.tasks.create!(
      account_id: @opportunity.account_id, kind: :call, assignee: @user, created_by: @user,
      due_at: Outsider::Crm::OpportunityForwarder::CONTACT_TASK_DUE.from_now,
      title: I18n.t('outsider_crm.forward.task_title', unit: origin.business_unit.name)
    )
  end
end
