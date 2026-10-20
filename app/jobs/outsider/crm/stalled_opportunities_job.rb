# OUTSIDER: roda a automação "negócio parado" (Outsider::Crm::StalledOpportunities) em todas as
# contas que a ligaram. Agendado no config/initializers/outsider_crm.rb.
class Outsider::Crm::StalledOpportunitiesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Outsider::Crm::StalledOpportunities.perform_all
  end
end
