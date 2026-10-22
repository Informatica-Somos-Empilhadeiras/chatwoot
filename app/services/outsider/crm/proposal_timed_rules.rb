# OUTSIDER: regras de automação com gatilho de tempo sobre propostas (Entrega 18), conferidas junto com
# as outras regras de tempo (Outsider::Crm::TimedRules):
# - proposal_no_reply: proposta enviada (sem aceite nem recusa) há mais de wait_hours, contando do
#   último envio que chegou ao cliente (ou de quando foi marcada como enviada);
# - proposal_expiring: proposta enviada cuja validade acaba em menos de wait_hours (ainda não vencida).
# Só proposta ligada a negócio aberto: a regra roda no negócio (condições de unidade, pipeline, etapa e
# valor mínimo valem para ele). Cada proposta dispara uma vez por situação: reenviar ou mudar a
# validade abre uma situação nova.
class Outsider::Crm::ProposalTimedRules
  LIMIT = 500
  TABLE = 'outsider_crm_proposals'.freeze
  LAST_SENT_SQL = "COALESCE((SELECT MAX(s.created_at) FROM outsider_crm_proposal_sends s WHERE s.proposal_id = #{TABLE}.id " \
                  "AND s.status = #{Outsider::Crm::ProposalSend.statuses[:delivered]}), #{TABLE}.sent_at)".freeze

  def initialize(account, rule)
    @account = account
    @rule = rule
  end

  # Devolve quantas vezes a regra rodou
  def perform
    candidates = candidates_scope.limit(LIMIT).to_a
    done = already_run(candidates)
    candidates.count do |proposal|
      key = key_for(proposal)
      next false if done.include?([proposal.opportunity_id, key])

      Outsider::Crm::RuleRunner.new(proposal.opportunity, @rule, key: key, proposal: proposal).perform
    end
  end

  private

  def expiring?
    @rule['trigger'] == 'proposal_expiring'
  end

  def key_for(proposal)
    expiring? ? "proposal:#{proposal.id}:until:#{proposal.valid_until.iso8601}" : "proposal:#{proposal.id}:sent:#{proposal.last_sent_at.utc.iso8601}"
  end

  def candidates_scope
    scope = base
    if expiring?
      limit = (Time.current + @rule['wait_hours'].to_i.hours).to_date
      scope.where(valid_until: Time.zone.today...limit).order(:valid_until)
    else
      limit = Time.current - @rule['wait_hours'].to_i.hours
      scope.where("#{LAST_SENT_SQL} < ?", limit).order(Arel.sql(LAST_SENT_SQL))
    end
  end

  def base
    opportunities = Outsider::Crm::Opportunity.open.where(account_id: @account.id)
    conditions = @rule['conditions'] || {}
    opportunities = opportunities.where(conditions.slice('business_unit_id', 'pipeline_id', 'stage_id').compact)
    opportunities = opportunities.where(value_cents: conditions['min_value_cents']..) if conditions['min_value_cents']
    Outsider::Crm::Proposal.sent.where(account_id: @account.id, opportunity_id: opportunities.select(:id))
                           .includes(opportunity: [:owner, :conversation])
                           .select("#{TABLE}.*, #{LAST_SENT_SQL} AS last_sent_at")
  end

  def already_run(proposals)
    Outsider::Crm::Activity.automation.where(opportunity_id: proposals.map(&:opportunity_id).uniq)
                           .where("outsider_crm_activities.metadata ->> 'rule' = 'custom'")
                           .where("outsider_crm_activities.metadata ->> 'rule_id' = ?", @rule['id'].to_s)
                           .pluck(:opportunity_id, Arel.sql("outsider_crm_activities.metadata ->> 'key'")).to_set
  end
end
