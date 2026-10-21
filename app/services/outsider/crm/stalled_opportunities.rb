# OUTSIDER: automação "negócio parado". Nas contas que ligaram a automação, cria uma tarefa de
# follow-up para o responsável de cada negócio aberto que está na mesma etapa há mais tempo que o
# limite: o prazo da etapa (sla_hours), quando ela tem um, ou os dias das configurações.
# Uma tarefa por passagem na etapa: depois de criada, só cria outra se o negócio mudar de etapa e
# parar de novo. Roda de hora em hora (StalledOpportunitiesJob) e pelo botão "Verificar agora".
class Outsider::Crm::StalledOpportunities
  LIMIT = 500

  def self.perform_all
    accounts = Account.where("internal_attributes -> 'outsider_crm_settings' ->> 'automation_stalled_task' = 'true'")
    Outsider::Crm::Switch.enabled_accounts(accounts).find_each do |account|
      new(account).perform
    end
  end

  def initialize(account)
    @account = account
    @settings = Outsider::Crm::Settings.new(account)
  end

  # Devolve quantas tarefas criou
  def perform
    return 0 unless @settings[:automation_stalled_task]

    candidates = stalled.limit(LIMIT).to_a
    flagged = already_flagged(candidates)
    I18n.with_locale(locale) do
      candidates.count { |opportunity| flagged.exclude?([opportunity.id, entered_at(opportunity)]) && create_task(opportunity) }
    end
  end

  private

  def stalled
    Outsider::Crm::Opportunity.open.where(account_id: @account.id).where.not(stage_changed_at: nil).joins(:stage)
                              .where('outsider_crm_opportunities.stage_changed_at < ?::timestamp - COALESCE(outsider_crm_stages.sla_hours * ' \
                                     "INTERVAL '1 hour', ? * INTERVAL '1 day')", Time.current, @settings[:automation_stalled_days])
                              .includes(:stage, :owner).order(:stage_changed_at)
  end

  def already_flagged(opportunities)
    Outsider::Crm::Activity.automation.where(opportunity_id: opportunities.map(&:id))
                           .where("outsider_crm_activities.metadata ->> 'rule' = 'stalled_task'")
                           .pluck(:opportunity_id, Arel.sql("outsider_crm_activities.metadata ->> 'stage_entered_at'")).to_set
  end

  def entered_at(opportunity)
    opportunity.stage_changed_at.utc.iso8601
  end

  def create_task(opportunity)
    days = ((Time.current - opportunity.stage_changed_at) / 1.day).floor
    Outsider::Crm::Opportunity.transaction do
      task = Outsider::Crm::Automations.as_system(nil) { build_task(opportunity, days) }
      Outsider::Crm::Automations.log(opportunity, 'stalled_task', stage: opportunity.stage.name, days: days, task_id: task.id,
                                                                  stage_entered_at: entered_at(opportunity))
    end
    true
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    false
  end

  def build_task(opportunity, days)
    opportunity.tasks.create!(
      account_id: @account.id, kind: :follow_up, due_at: Time.current, assignee: crm_owner(opportunity),
      title: I18n.t('outsider_crm.automations.stalled_task_title', stage: opportunity.stage.name),
      description: I18n.t('outsider_crm.automations.stalled_task_description', days: days)
    )
  end

  # responsável com o CRM desligado (Outsider::Crm::Switch) não recebe tarefa: ela fica sem dono
  def crm_owner(opportunity)
    owner = opportunity.owner
    owner if owner && switch.disabled_agent_ids.exclude?(owner.id)
  end

  def switch
    @switch ||= Outsider::Crm::Switch.new(@account)
  end

  def locale
    I18n.available_locales.map(&:to_s).include?(@account.locale.to_s) ? @account.locale : I18n.default_locale
  end
end
