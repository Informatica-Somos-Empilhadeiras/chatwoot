# OUTSIDER: linha do tempo de uma oportunidade e notas internas do CRM. Quem enxerga o negócio
# escreve nota, menos no negócio já encaminhado (a conversa segue no destino). A nota fica só no
# CRM: não vira mensagem do Chatwoot e nunca vai para o cliente.
class Api::V1::Accounts::Outsider::Crm::OpportunityActivitiesController < Api::V1::Accounts::Outsider::Crm::OpportunityChildController
  PER_PAGE = 30

  def index
    activities = @opportunity.activities.includes(:user).order(id: :desc)
    activities = activities.where(id: ...params[:before_id].to_i) if params[:before_id].present?
    page = activities.limit(PER_PAGE + 1).to_a
    render json: { payload: page.first(PER_PAGE).map { |activity| serialize(activity) }, meta: { has_more: page.size > PER_PAGE } }
  end

  def create
    if @opportunity.forwarded?
      return render json: { error: 'forwarded_locked', message: I18n.t('outsider_crm.errors.forwarded_locked') }, status: :unprocessable_entity
    end

    activity = @opportunity.activities.create!(
      account: Current.account, user: Current.user, kind: :note, body: params.require(:activity)[:body].to_s.strip, metadata: note_metadata
    )
    render json: serialize(activity), status: :created
  end

  def destroy
    activity = @opportunity.activities.find(params[:id])
    return render_forbidden unless crm_access.delete_activity?(activity)

    activity.destroy!
    head :no_content
  end

  private

  # Nota escrita na conversa guarda o número dela, para a linha do tempo mostrar de onde veio
  def note_metadata
    display_id = params[:activity][:conversation_display_id]
    return {} if display_id.blank?

    conversation = Current.account.conversations.find_by(display_id: display_id, contact_id: @opportunity.contact_id)
    conversation ? { conversation_display_id: conversation.display_id } : {}
  end

  def serialize(activity)
    ::Outsider::Crm::Serializer.activity(activity, access: crm_access)
  end
end
