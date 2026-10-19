# OUTSIDER: cria uma oportunidade para um contato do Chatwoot. Reaproveita a jornada aberta do
# contato (ou abre uma) e completa pipeline, etapa e responsável com padrões da unidade.
class Outsider::Crm::OpportunityBuilder
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params
  end

  def perform
    Outsider::Crm::Opportunity.transaction do
      opportunity = Outsider::Crm::Opportunity.new(@params.except(:pipeline_id, :stage_id))
      opportunity.assign_attributes(account: @account, contact: contact, created_by: @user, owner_id: @params[:owner_id] || @user.id)
      opportunity.pipeline = pipeline(opportunity.business_unit_id)
      opportunity.stage = stage(opportunity.pipeline)
      opportunity.journey = journey
      opportunity.save!
      opportunity
    end
  end

  private

  def contact
    @contact ||= @account.contacts.find(@params[:contact_id])
  end

  def pipeline(unit_id)
    pipelines = Outsider::Crm::Pipeline.where(account_id: @account.id, business_unit_id: unit_id)
    return pipelines.find_by(id: @params[:pipeline_id]) if @params[:pipeline_id].present?

    pipelines.active.ordered.first
  end

  def stage(pipeline)
    return if pipeline.nil?
    return pipeline.stages.find_by(id: @params[:stage_id]) if @params[:stage_id].present?

    pipeline.first_open_stage
  end

  def journey
    Outsider::Crm::Journey.open.where(account_id: @account.id, contact_id: contact.id).order(:id).last ||
      Outsider::Crm::Journey.create!(account: @account, contact: contact, company_id: contact.company_id,
                                     origin: @params[:conversation_id].present? ? 'conversation' : 'manual')
  end
end
