# OUTSIDER: regras de automação com gatilho de tempo (ver AutomationRules), conferidas de hora em hora
# junto com a automação de negócio parado e pelo botão "Verificar agora":
# - stalled: negócio aberto na mesma etapa há mais de wait_hours;
# - no_next_task: negócio aberto sem tarefa pendente há mais de wait_hours (contando da última
#   tarefa concluída ou, se nunca teve, da criação do negócio).
# Cada regra roda uma vez por situação: a marca (key) é a entrada na etapa ou o momento em que o
# negócio ficou sem tarefa, gravada na linha do tempo. Mudou de etapa ou ganhou e concluiu uma
# tarefa nova, a situação é outra e a regra pode rodar de novo.
class Outsider::Crm::TimedRules
  LIMIT = 500
  TABLE = 'outsider_crm_opportunities'.freeze
  IDLE_SINCE_SQL = 'COALESCE((SELECT MAX(t.completed_at) FROM outsider_crm_tasks t WHERE t.opportunity_id = ' \
                   "#{TABLE}.id), #{TABLE}.created_at)".freeze
  NO_PENDING_SQL = "NOT EXISTS (SELECT 1 FROM outsider_crm_tasks t WHERE t.opportunity_id = #{TABLE}.id AND t.completed_at IS NULL)".freeze

  def self.perform_all
    accounts = Account.where("jsonb_array_length(COALESCE(internal_attributes -> '#{Outsider::Crm::AutomationRules::KEY}', '[]'::jsonb)) > 0")
    Outsider::Crm::Switch.enabled_accounts(accounts).find_each.sum { |account| new(account).perform }
  end

  def initialize(account)
    @account = account
  end

  # Devolve quantas vezes alguma regra rodou
  def perform
    Outsider::Crm::AutomationRules.new(@account).active(Outsider::Crm::AutomationRules::TIMED_TRIGGERS).sum { |rule| perform_rule(rule) }
  end

  private

  def perform_rule(rule)
    candidates = candidates(rule).limit(LIMIT).to_a
    done = already_run(rule, candidates)
    candidates.count do |opportunity|
      key = opportunity.reference_at.utc.iso8601
      done.exclude?([opportunity.id, key]) && Outsider::Crm::RuleRunner.new(opportunity, rule, key: key).perform
    end
  end

  def candidates(rule)
    limit = Time.current - rule['wait_hours'].to_i.hours
    scope = filtered(rule)
    if rule['trigger'] == 'stalled'
      scope.where.not(stage_changed_at: nil).where("#{TABLE}.stage_changed_at < ?", limit)
           .select("#{TABLE}.*, #{TABLE}.stage_changed_at AS reference_at").order(:stage_changed_at)
    else
      scope.where(NO_PENDING_SQL).where("#{IDLE_SINCE_SQL} < ?", limit)
           .select("#{TABLE}.*, #{IDLE_SINCE_SQL} AS reference_at").order(Arel.sql(IDLE_SINCE_SQL))
    end
  end

  def filtered(rule)
    conditions = rule['conditions'] || {}
    scope = Outsider::Crm::Opportunity.open.where(account_id: @account.id).includes(:owner, :conversation)
    scope = scope.where(conditions.slice('business_unit_id', 'pipeline_id', 'stage_id').compact)
    conditions['min_value_cents'] ? scope.where(value_cents: conditions['min_value_cents']..) : scope
  end

  def already_run(rule, opportunities)
    Outsider::Crm::Activity.automation.where(opportunity_id: opportunities.map(&:id))
                           .where("outsider_crm_activities.metadata ->> 'rule' = 'custom'")
                           .where("outsider_crm_activities.metadata ->> 'rule_id' = ?", rule['id'].to_s)
                           .pluck(:opportunity_id, Arel.sql("outsider_crm_activities.metadata ->> 'key'")).to_set
  end
end
