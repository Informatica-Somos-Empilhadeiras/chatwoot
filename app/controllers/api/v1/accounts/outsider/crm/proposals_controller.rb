# OUTSIDER: propostas de venda e locação. Lista com busca e filtros (só as que a pessoa pode ver), criar,
# alterar, mudar a situação, apagar rascunho e ver o PDF, montado na hora (nada é gravado para visualizar).
class Api::V1::Accounts::Outsider::Crm::ProposalsController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  PER_PAGE = 30
  FILTERS = %w[owner_id contact_id opportunity_id].freeze
  SORTS = { 'recent' => { created_at: :desc }, 'number' => { number: :desc }, 'value' => { total_cents: :desc } }.freeze

  before_action :fetch_proposal, only: [:show, :update, :destroy, :status, :pdf]
  before_action :ensure_can_edit, only: [:update, :status]

  def index
    proposals = filtered.includes(:contact, :owner, :opportunity, :sends).order(SORTS.fetch(params[:sort], SORTS['recent'])).order(id: :desc)
    page = [params[:page].to_i, 1].max
    render json: {
      meta: { count: proposals.count, total_cents: proposals.sum(:total_cents), page: page, per_page: PER_PAGE },
      payload: proposals.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map { |proposal| serializer.proposal_row(proposal, access: proposal_access) }
    }
  end

  def show
    render json: serializer.proposal(@proposal, access: proposal_access)
  end

  # Dados com que a proposta nova abre (contato, negócio e tipo escolhidos)
  def prefill
    contact = Current.account.contacts.find(params.require(:contact_id))
    opportunity = crm_scope(::Outsider::Crm::Opportunity).find(params[:opportunity_id]) if params[:opportunity_id].present?
    return render_forbidden if opportunity && !crm_access.view_opportunity?(opportunity)

    render json: ::Outsider::Crm::ProposalPrefill.new(Current.account_user, contact: contact, opportunity: opportunity, kind: params[:kind])
  end

  def create
    proposal = saver.create(proposal_params)
    render json: serializer.proposal(proposal, access: proposal_access), status: :created
  end

  def update
    unless proposal_access.edit_content?(@proposal)
      return render json: { error: 'locked', message: I18n.t('outsider_crm.proposals.locked') },
                    status: :unprocessable_entity
    end

    saver.update(@proposal, proposal_params)
    render json: serializer.proposal(@proposal.reload, access: proposal_access)
  end

  def status
    saver.change_status(@proposal, params.require(:status))
    render json: serializer.proposal(@proposal.reload, access: proposal_access)
  end

  def destroy
    return render_forbidden unless proposal_access.delete?(@proposal)

    @proposal.destroy!
    head :no_content
  end

  def pdf
    document = ::Outsider::Crm::ProposalPdf.new(@proposal)
    send_data document.render, filename: document.filename, type: 'application/pdf', disposition: params[:download].present? ? 'attachment' : 'inline'
  end

  private

  def serializer
    ::Outsider::Crm::ProposalSerializer
  end

  def saver
    ::Outsider::Crm::ProposalSaver.new(Current.account_user)
  end

  def fetch_proposal
    @proposal = proposal_access.proposals.find_by(id: params[:id])
    head :not_found if @proposal.nil?
  end

  def ensure_can_edit
    render_forbidden unless proposal_access.edit?(@proposal)
  end

  def filtered
    scope = proposal_access.proposals.where(params.slice(*FILTERS).permit(*FILTERS).to_h.compact_blank)
    scope = status_filter(scope, params[:status].to_s)
    search(kind_and_period(scope), params[:q].to_s.strip)
  end

  def kind_and_period(scope)
    scope = scope.where(kind: params[:kind]) if ::Outsider::Crm::Proposal.kinds.key?(params[:kind].to_s)
    scope = scope.where(issued_on: params[:from]..) if params[:from].present?
    scope = scope.where(issued_on: ..params[:to]) if params[:to].present?
    scope
  end

  # Vencida não é uma situação gravada: rascunho ou enviada com a validade passada
  def status_filter(scope, status)
    return expired(scope) if status == 'expired'
    return scope unless ::Outsider::Crm::Proposal.statuses.key?(status)

    scope.where(status: status)
  end

  def expired(scope)
    scope.where(status: [:draft, :sent]).where(valid_until: ...Time.zone.today)
  end

  # Número, empresa do cliente, nome do contato, título ou máquina dos itens
  def search(scope, query)
    return scope if query.blank?
    return scope.where(number: query.to_i) if query.match?(/\A\d+\z/) && scope.exists?(number: query.to_i)

    like = "%#{::Outsider::Crm::Proposal.sanitize_sql_like(query)}%"
    scope.left_joins(:contact).where(
      "outsider_crm_proposals.title ILIKE :q OR outsider_crm_proposals.customer ->> 'company' ILIKE :q OR contacts.name ILIKE :q OR " \
      'EXISTS (SELECT 1 FROM outsider_crm_proposal_items i WHERE i.proposal_id = outsider_crm_proposals.id AND i.description ILIKE :q)',
      q: like
    )
  end

  def proposal_params
    params.require(:proposal).permit(
      :kind, :template_id, :title, :contact_id, :opportunity_id, :business_unit_id, :owner_id, :issued_on, :valid_until, :notes,
      customer: ::Outsider::Crm::Proposal::CUSTOMER_KEYS, signer: ::Outsider::Crm::Proposal::SIGNER_KEYS,
      conditions: [:label, :text], create_opportunity: [:business_unit_id, :pipeline_id],
      items: [:id, :product_id, :description, :quantity, :unit_price_cents, :discount_cents, :show_details, :refresh_details]
    )
  end
end
