# OUTSIDER: move um card do Kanban para uma etapa e posição. Renumera só os cards abertos da
# etapa de destino; a troca de etapa passa pelo modelo (auditoria, linha do tempo, status).
class Outsider::Crm::OpportunityMover
  def initialize(opportunity, stage:, index:)
    @opportunity = opportunity
    @stage = stage
    @index = index.to_i
  end

  def perform
    Outsider::Crm::Opportunity.transaction do
      siblings = Outsider::Crm::Opportunity.open.where(stage_id: @stage.id).where.not(id: @opportunity.id)
                                           .order(:position, :id).lock.pluck(:id)
      ordered = siblings.insert(@index.clamp(0, siblings.size), @opportunity.id)
      @opportunity.update!(stage: @stage, position: ordered.index(@opportunity.id))
      renumber(ordered - [@opportunity.id], ordered)
    end
    @opportunity
  end

  private

  # update_all de propósito: só a ordem muda, sem auditoria nem linha do tempo
  def renumber(ids, ordered)
    ids.each do |id|
      Outsider::Crm::Opportunity.where(id: id).update_all(position: ordered.index(id)) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
