# OUTSIDER: oportunidades. Cada um vê as das suas unidades; cria em unidade da qual é membro;
# edita conforme Outsider::Crm::Access. Trocar de unidade é encaminhamento, não edição.
class Api::V1::Accounts::Outsider::Crm::OpportunitiesController < Api::V1::Accounts::Outsider::Crm::BaseController
  PER_PAGE = 50
  SORTS = { 'recent' => { updated_at: :desc }, 'value' => { value_cents: :desc }, 'close' => { expected_close_on: :asc },
            'created' => { created_at: :desc } }.freeze

  BOARD_LIMIT = 100

  before_action :fetch_opportunity, only: [:show, :update, :destroy, :move]
  before_action :ensure_can_edit, only: [:update, :move]
  before_action :ensure_can_delete, only: [:destroy]

  def index
    opportunities = filtered.includes(:contact, :owner, :stage).order(SORTS.fetch(params[:sort], SORTS['recent'])).order(id: :desc)
    page = [params[:page].to_i, 1].max
    render json: {
      meta: { count: opportunities.count, page: page, per_page: PER_PAGE },
      payload: serialize_list(opportunities.offset((page - 1) * PER_PAGE).limit(PER_PAGE))
    }
  end

  def show
    render json: serialize(@opportunity)
  end

  # Kanban: colunas são as etapas abertas do pipeline, com os negócios abertos de cada uma
  def board
    pipeline = crm_scope(::Outsider::Crm::Pipeline).where(business_unit_id: crm_access.visible_unit_ids).find(params.require(:pipeline_id))
    scope = filtered.open.where(pipeline_id: pipeline.id).includes(:contact, :owner, :stage)
    totals = scope.group(:stage_id).pluck(:stage_id, Arel.sql('COUNT(*)'), Arel.sql('SUM(value_cents)')).index_by(&:first)
    cards = board_cards(scope, pipeline.stages.select(&:kind_open?))
    render json: { pipeline_id: pipeline.id, stages: cards.map { |stage, list| board_column(stage, list, totals) } }
  end

  def summary
    scope = crm_access.metrics(filtered.unscope(where: :status))
    render json: ::Outsider::Crm::Metrics.new(scope, period: params[:period]).to_h
  end

  def export
    csv = ::Outsider::Crm::OpportunitiesCsv.new(filtered.order(SORTS.fetch(params[:sort], SORTS['recent']))).generate
    send_data "\uFEFF#{csv}", filename: "negocios-#{Time.zone.today}.csv", type: 'text/csv; charset=utf-8'
  end

  def move
    stage = crm_scope(::Outsider::Crm::Stage).find_by(id: params.require(:stage_id), pipeline_id: @opportunity.pipeline_id)
    return render json: { error: 'invalid_stage' }, status: :unprocessable_entity if stage.nil?

    ::Outsider::Crm::OpportunityMover.new(@opportunity, stage: stage, index: params[:index]).perform
    render json: serialize(@opportunity.reload)
  end

  def create
    unit_id = params.require(:opportunity)[:business_unit_id].to_i
    return render_forbidden unless crm_access.member_of?(unit_id) && owner_allowed?(unit_id)

    opportunity = ::Outsider::Crm::OpportunityBuilder.new(account: Current.account, user: Current.user, params: create_params).perform
    render json: serialize(opportunity), status: :created
  end

  def update
    return render_forbidden unless owner_allowed?(@opportunity.business_unit_id, @opportunity.owner_id)
    # encaminhar tem rota própria (opportunity_forwards), com destino, motivo e tentativa
    return render json: { error: 'use_forward' }, status: :unprocessable_entity if params[:opportunity][:status].to_s == 'forwarded'

    @opportunity.update!(update_params)
    render json: serialize(@opportunity.reload)
  end

  # Negócio que entrou ou saiu por encaminhamento não se apaga (restrict_with_error no modelo)
  def destroy
    remover.opportunity(@opportunity)
    head :no_content
  end

  private

  # Lista, Kanban, indicadores e CSV da tela principal: o vendedor vê só os seus; o gestor, também os
  # das unidades que gerencia (Access#main_list). owner_id=none filtra os negócios sem responsável.
  def filtered
    scope = crm_access.main_list(crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity)))
    %i[business_unit_id pipeline_id stage_id contact_id conversation_id status].each do |filter|
      scope = scope.where(filter => params[filter]) if params[filter].present?
    end
    scope = scope.where(owner_id: params[:owner_id] == 'none' ? nil : params[:owner_id]) if params[:owner_id].present?
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

  def ensure_can_delete
    render_forbidden unless crm_access.delete_opportunity?(@opportunity)
  end

  # Vendedor só fica com oportunidades no próprio nome; gestor e administrador escolhem o responsável
  def owner_allowed?(unit_id, current_owner_id = nil)
    owner_id = params.fetch(:opportunity, {})[:owner_id]
    return true if owner_id.blank? || owner_id.to_i == current_owner_id || crm_access.manage_unit?(unit_id)

    owner_id.to_i == Current.user.id
  end

  def create_params
    attributes = params.require(:opportunity).permit(
      :business_unit_id, :pipeline_id, :stage_id, :contact_id, :owner_id, :title,
      :expected_close_on, :probability, custom_fields: {}
    ).to_h.symbolize_keys
    attributes.merge(value_attributes).merge(conversation_attributes)
  end

  # O navegador conhece a conversa pelo número que aparece na tela (display_id), não pelo id interno
  def conversation_attributes
    display_id = params[:opportunity][:conversation_display_id]
    return {} if display_id.blank?

    { conversation_id: Current.account.conversations.find_by!(display_id: display_id).id }
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

  # Até BOARD_LIMIT cards por etapa, serializados juntos (tarefas pendentes numa consulta só)
  def board_cards(scope, stages)
    records = stages.index_with { |stage| scope.where(stage_id: stage.id).order(:position, :id).limit(BOARD_LIMIT).to_a }
    serialized = serialize_list(records.values.flatten).index_by { |card| card['id'] }
    records.transform_values { |list| list.map { |opportunity| serialized[opportunity.id] } }
  end

  def board_column(stage, cards, totals)
    _id, count, total = totals[stage.id]
    ::Outsider::Crm::Serializer.stage(stage).merge(count: count.to_i, total_cents: total.to_i, opportunities: cards)
  end

  def serialize(opportunity)
    ::Outsider::Crm::Serializer.opportunity(opportunity, access: crm_access)
  end

  def serialize_list(opportunities)
    ::Outsider::Crm::Serializer.opportunities(opportunities, access: crm_access)
  end
end
