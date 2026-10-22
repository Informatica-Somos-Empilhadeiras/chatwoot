# OUTSIDER: proposta mais recente de cada negócio (Entrega 18), para o selo no card do Kanban, na tabela
# e na aba CRM da conversa. Uma consulta para a lista inteira e só com as propostas que a pessoa pode ver
# (Outsider::Crm::ProposalAccess); canceladas não contam.
module Outsider::Crm::ProposalStats
  COLUMNS = %i[id opportunity_id number status sent_at valid_until total_cents created_at].freeze

  module_function

  # access: Outsider::Crm::Access de quem vê (sem ele, nenhum selo)
  def for(opportunity_ids, access)
    return {} if access.nil? || opportunity_ids.empty?

    scope = Outsider::Crm::ProposalAccess.new(access.account_user).proposals
                                         .where(opportunity_id: opportunity_ids).where.not(status: :canceled)
    scope.order(created_at: :desc, id: :desc).select(*COLUMNS).group_by(&:opportunity_id)
         .transform_values { |proposals| summary(proposals) }
  end

  def summary(proposals)
    latest = proposals.first
    {
      id: latest.id, number: latest.number, status: latest.display_status, sent_at: latest.sent_at,
      valid_until: latest.valid_until, total_cents: latest.total_cents, count: proposals.size
    }
  end
end
