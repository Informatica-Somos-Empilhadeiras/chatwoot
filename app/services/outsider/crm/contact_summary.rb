# OUTSIDER: resumo do CRM de um contato do Chatwoot (aba CRM da conversa e painel do contato).
# Só entram oportunidades das unidades que o usuário enxerga. A principal é a aberta ligada à
# conversa atual; sem ela, a aberta atualizada por último.
class Outsider::Crm::ContactSummary
  GROUP_SUFFIX = '@g.us'.freeze
  HISTORY_LIMIT = 50

  def self.group?(contact)
    contact.identifier.to_s.end_with?(GROUP_SUFFIX)
  end

  def initialize(contact, access:, conversation_id: nil)
    @contact = contact
    @access = access
    @conversation_id = conversation_id.presence&.to_i
  end

  def to_h
    open = opportunities.select(&:open?)
    won = opportunities.select(&:won?)
    {
      contact_id: @contact.id,
      group: self.class.group?(@contact),
      open_count: open.size,
      open_value_cents: open.sum(&:value_cents),
      won_count: won.size,
      won_value_cents: won.sum(&:value_cents),
      primary_id: primary(open)&.id,
      creatable_unit_ids: creatable_unit_ids(open),
      opportunities: opportunities.map { |opportunity| Outsider::Crm::Serializer.opportunity(opportunity, access: @access) }
    }
  end

  private

  def opportunities
    @opportunities ||= @access.opportunities(Outsider::Crm::Opportunity.where(account_id: @contact.account_id, contact_id: @contact.id))
                              .includes(:contact, :owner, :stage)
                              .order(Arel.sql('CASE WHEN outsider_crm_opportunities.status = 0 THEN 0 ELSE 1 END'),
                                     Arel.sql('COALESCE(outsider_crm_opportunities.closed_at, outsider_crm_opportunities.updated_at) DESC'))
                              .limit(HISTORY_LIMIT).to_a
  end

  def primary(open)
    open.find { |opportunity| @conversation_id && opportunity.conversation_id == @conversation_id } ||
      open.max_by(&:updated_at)
  end

  # Unidades com pipeline ativo em que o usuário pode abrir negócio para o contato
  # (uma oportunidade aberta por unidade; grupos não têm negócio)
  def creatable_unit_ids(open)
    return [] if self.class.group?(@contact)

    member_units = @access.administrator? ? @access.visible_unit_ids : @access.member_unit_ids
    with_pipeline = Outsider::Crm::Pipeline.active.where(account_id: @contact.account_id, business_unit_id: member_units)
                                           .distinct.pluck(:business_unit_id)
    with_pipeline - open.map(&:business_unit_id)
  end
end
