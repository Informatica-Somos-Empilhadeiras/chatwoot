# OUTSIDER: roda a automação "negócio parado" (Outsider::Crm::StalledOpportunities) nas contas que a
# ligaram e as regras com gatilho de tempo (Outsider::Crm::TimedRules). Agendado no
# config/initializers/outsider_crm.rb.
class Outsider::Crm::StalledOpportunitiesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Outsider::Crm::StalledOpportunities.perform_all
    Outsider::Crm::TimedRules.perform_all
  end
end
