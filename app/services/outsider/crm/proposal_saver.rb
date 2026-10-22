# OUTSIDER: cria e altera propostas. Confere tudo o que chega do navegador (contato, negócio, unidade,
# modelo, produtos e responsável precisam ser da conta e visíveis para quem salva), recalcula os totais
# e, se pedido, cria o negócio junto (valor = total da proposta). Proposta ligada a negócio aparece na
# linha do tempo dele.
class Outsider::Crm::ProposalSaver
  class Forbidden < StandardError; end

  ITEM_LIMIT = Outsider::Crm::Proposal::MAX_ITEMS
  TEXT_FIELDS = %i[title notes issued_on valid_until kind customer conditions signer].freeze

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
  end

  def create(params)
    params = params.to_h.with_indifferent_access
    Outsider::Crm::Proposal.transaction do
      proposal = Outsider::Crm::Proposal.new(account: @account, created_by: @user, status: :draft)
      proposal.contact = @account.contacts.find(params[:contact_id])
      proposal.owner_id = owner_id(params[:owner_id])
      assign(proposal, params)
      proposal.opportunity = create_opportunity(proposal, params[:create_opportunity]) if params[:create_opportunity].present?
      proposal.save!
      log(proposal, 'created') if proposal.opportunity
      proposal
    end
  end

  def update(proposal, params)
    params = params.to_h.with_indifferent_access
    Outsider::Crm::Proposal.transaction do
      previous_opportunity_id = proposal.opportunity_id
      proposal.owner_id = owner_id(params[:owner_id]) if params.key?(:owner_id) && access.assign_owner?
      assign(proposal, params)
      proposal.opportunity = create_opportunity(proposal, params[:create_opportunity]) if params[:create_opportunity].present?
      proposal.save!
      log(proposal, 'linked') if proposal.opportunity_id && proposal.opportunity_id != previous_opportunity_id
      proposal
    end
  end

  # Aceita, recusada, cancelada, enviada ou de volta a rascunho
  def change_status(proposal, status)
    raise Forbidden, 'status' unless Outsider::Crm::Proposal.statuses.key?(status.to_s)

    proposal.status = status
    proposal.sent_at ||= Time.current if proposal.sent?
    proposal.decided_at = proposal.accepted? || proposal.rejected? ? Time.current : nil
    proposal.save!
    log(proposal, status.to_s) if proposal.opportunity
    proposal
  end

  private

  def assign(proposal, params)
    TEXT_FIELDS.each { |field| proposal.public_send("#{field}=", params[field]) if params.key?(field) && !params[field].nil? }
    proposal.issued_on ||= Time.zone.today
    proposal.template = template(proposal, params[:template_id])
    assign_links(proposal, params)
    assign_items(proposal, params[:items]) if params.key?(:items)
    proposal.recalculate_total
  end

  def assign_links(proposal, params)
    proposal.business_unit_id = unit_id(params[:business_unit_id]) if params.key?(:business_unit_id)
    proposal.opportunity = opportunity(params[:opportunity_id]) if params.key?(:opportunity_id)
  end

  def assign_items(proposal, rows)
    rows = Array(rows)
    raise Forbidden, 'items' if rows.size > ITEM_LIMIT

    existing = proposal.items.index_by(&:id)
    kept = rows.each_with_index.map { |row, index| assign_item(proposal, existing, row.to_h.with_indifferent_access, index) }
    (existing.values - kept).each(&:mark_for_destruction)
  end

  def assign_item(proposal, existing, row, index)
    item = existing[row[:id].to_i] || proposal.items.build(account: @account)
    product = product(row[:product_id], item)
    refresh = item.new_record? || item.product_id != product&.id || boolean(row[:refresh_details])
    item.assign_attributes(item_values(row, product).merge(product: product, position: index))
    item.details = product ? product.details : {} if refresh
    item
  end

  def item_values(row, product)
    {
      description: row[:description].to_s.strip.presence || product&.name.to_s,
      quantity: row[:quantity].presence || 1,
      unit_price_cents: row[:unit_price_cents].to_i,
      discount_cents: row[:discount_cents].to_i,
      # sem escolha, máquina mostra as características e acessório não
      show_details: row.key?(:show_details) ? boolean(row[:show_details]) : product&.machine? || false
    }
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  # Produto do catálogo da conta; inativo só vale se o item já era dele
  def product(id, item)
    return if id.blank?

    product = Outsider::Crm::Product.find_by!(account_id: @account.id, id: id)
    raise Forbidden, 'product' unless product.active? || item.product_id == product.id

    product
  end

  # Sem modelo escolhido, fica o que já tinha (se for do tipo) ou o primeiro ativo do tipo; os padrão existem
  # desde a primeira visita
  def template(proposal, id)
    templates = Outsider::Crm::ProposalTemplate.where(account_id: @account.id)
    return templates.find(id) if id.present?
    return proposal.template if proposal.template&.kind == proposal.kind

    templates.active.ordered.find_by(kind: proposal.kind || 'sale')
  end

  def unit_id(id)
    return if id.blank?

    raise Forbidden, 'unit' unless crm_access.member_of?(id.to_i) && Outsider::Crm::BusinessUnit.exists?(account_id: @account.id, id: id)

    id.to_i
  end

  # Negócio do mesmo contato, que a pessoa consegue ver
  def opportunity(id)
    return if id.blank?

    opportunity = Outsider::Crm::Opportunity.find_by!(account_id: @account.id, id: id)
    raise Forbidden, 'opportunity' unless crm_access.view_opportunity?(opportunity)

    opportunity
  end

  def create_opportunity(proposal, data)
    data = data.to_h.with_indifferent_access
    raise Forbidden, 'unit' unless crm_access.member_of?(data[:business_unit_id].to_i)

    Outsider::Crm::OpportunityBuilder.new(
      account: @account, user: @user,
      params: { contact_id: proposal.contact_id, business_unit_id: data[:business_unit_id], pipeline_id: data[:pipeline_id],
                title: proposal.title, value_cents: proposal.total_cents, owner_id: proposal.owner_id || @user.id }
    ).perform
  end

  def owner_id(id)
    return @user.id unless access.assign_owner? && id.present?

    raise Forbidden, 'owner' unless @account.account_users.exists?(user_id: id)

    id.to_i
  end

  def log(proposal, action)
    proposal.opportunity.activities.create!(
      account_id: @account.id, user: @user, kind: :proposal,
      metadata: { action: action, proposal_id: proposal.id, number: proposal.number, total_cents: proposal.total_cents }
    )
  end

  def access
    @access ||= Outsider::Crm::ProposalAccess.new(@account_user)
  end

  def crm_access
    @crm_access ||= Outsider::Crm::Access.new(@account_user)
  end
end
