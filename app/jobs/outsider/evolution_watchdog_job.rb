# OUTSIDER: roda o vigia das conexões da Evolution (Outsider::EvolutionWatchdog) a cada minuto.
# Agendado no config/initializers/outsider_message_delivery.rb.
class Outsider::EvolutionWatchdogJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Outsider::EvolutionWatchdog.new.perform
  end
end
