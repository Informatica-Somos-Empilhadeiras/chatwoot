# OUTSIDER: oportunidades. Cada um vê as das suas unidades; cria em unidade da qual é membro;
# edita conforme Outsider::Crm::Access. Trocar de unidade é encaminhamento, não edição.
class Api::V1::Accounts::Outsider::Crm::OpportunitiesController < Api::V1::Accounts::Outsider::Crm::BaseController
  PER_PAGE = 50
  SORTS = { 'recent' => { updated_at: :desc }, 'value' => { value_cents: :desc }, 'close' => { expected_close_on: :asc },
            'created' => { created_at: :desc } }.freeze

  before_action :fetch_opportunity, only: [:show, :update, :destroy]
  before_action :ensure_can_edit, only: [:update]
  before_action :ensure_crm_admin, only: [:destroy]

  def index
    opportunities = filtered.includes(:contact, :owner, :stage).order(SORTS.fetch(params[:sort], SORTS['recent'])).order(id: :desc)
    page = [params[:page].to_i, 1].max
    render json: {
      meta: { count: opportunities.count, page: page, per_page: PER_PAGE },
      payload: opportunities.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map { |opportunity| serialize(opportunity) }
    }
  end

  def show
    render json: serialize(@opportunity)
  end

  def create
    unit_id = params.require(:opportunity)[:business_unit_id].to_i
    return render_forbidden unless crm_access.member_of?(unit_id) && owner_allowed?(unit_id)

    opportunity = ::Outsider::Crm::OpportunityBuilder.new(account: Current.account, user: Current.user, params: create_params).perform
    render json: serialize(opportunity), status: :created
  end

  def update
    return render_forbidden unless owner_allowed?(@opportunity.business_unit_id, @opportunity.owner_id)

    @opportunity.update!(update_params)
    render json: serialize(@opportunity.reload)
  end

  def destroy
    @opportunity.destroy!
    head :no_content
  end

  private

  def filtered
    scope = crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity))
    %i[business_unit_id pipeline_id stage_id owner_id contact_id conversation_id status].each do |filter|
      scope = scope.where(filter => params[filter]) if params[filter].present?
    end
    scope = search(scope) if params[:q].present?
    scope
  end

  def search(scope)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
    contact_ids = Current.account.contacts.where('name ILIKE :term OR phone_number ILIKE :term OR email ILIKE :term', term: term).select(:id)
    scope.where('outsider_crm_opportunities.title ILIKE :term', term: term).or(scope.where(contact_id: contact_ids))
  end

  def fetch_opportunity
    @opportunity = crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity)).find(params[:id])
  end

  def ensure_can_edit
    render_forbidden unless crm_access.edit_opportunity?(@opportunity)
  end

  # Vendedor só fica com oportunidades no próprio nome; gestor e administrador escolhem o responsável
  def owner_allowed?(unit_id, current_owner_id = nil)
    owner_id = params.fetch(:opportunity, {})[:owner_id]
    return true if owner_id.blank? || owner_id.to_i == current_owner_id || crm_access.manage_unit?(unit_id)

    owner_id.to_i == Current.user.id
  end

  def create_params
    attributes = params.require(:opportunity).permit(
      :business_unit_id, :pipeline_id, :stage_id, :contact_id, :conversation_id, :owner_id, :title,
      :expected_close_on, :probability, custom_fields: {}
    ).to_h.symbolize_keys
    attributes.merge(value_attributes)
  end

  def update_params
    attributes = params.require(:opportunity).permit(
      :stage_id, :owner_id, :title, :expected_close_on, :probability, :status, :lost_reason_id, :position, custom_fields: {}
    )
    attributes = attributes.merge(value_attributes)
    attributes[:stage_id] = valid_stage_id(attributes[:stage_id]) if attributes.key?(:stage_id)
    attributes
  end

  # Valor chega em reais ("68000,50" ou 68000.5) e é guardado em centavos
  def value_attributes
    value = params.fetch(:opportunity, {})[:value]
    return {} if value.nil?

    normalized = value.to_s.strip
    normalized = normalized.delete('.').tr(',', '.') if normalized.include?(',')
    { value_cents: (BigDecimal(normalized) * 100).round.to_i }
  rescue ArgumentError
    { value_cents: -1 }
  end

  # A etapa precisa ser do mesmo pipeline; senão o modelo recusa (stage inválido)
  def valid_stage_id(stage_id)
    stage_id.presence && crm_scope(::Outsider::Crm::Stage).find_by(id: stage_id)&.id
  end

  def serialize(opportunity)
    ::Outsider::Crm::Serializer.opportunity(opportunity, access: crm_access)
  end
end
