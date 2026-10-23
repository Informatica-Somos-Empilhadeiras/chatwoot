# OUTSIDER: mensagens do WhatsApp chegando na hora e sem sumir.
# - Outsider::InstantBroadcast: mensagem e conversa novas vão para a tela sem esperar a fila do Sidekiq
# - Outsider::EvolutionWatchdogJob: a cada minuto, reconecta instância da Evolution presa ou surda
#   (ver app/services/outsider/evolution_watchdog.rb). Para tirar o agendamento:
#   Sidekiq::Cron::Job.destroy('outsider_evolution_watchdog_job').
Rails.application.config.to_prepare do
  ActionCableListener.prepend(Outsider::InstantBroadcast) unless ActionCableListener < Outsider::InstantBroadcast
end

Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_evolution_watchdog_job', cron: '* * * * *',
                              class: 'Outsider::EvolutionWatchdogJob', queue: 'scheduled_jobs')
  end
end
