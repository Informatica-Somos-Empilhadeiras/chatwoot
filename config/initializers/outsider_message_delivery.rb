# OUTSIDER: mensagens do WhatsApp chegando na hora, sem sumir e com a entrega conferida.
# - Outsider::InstantBroadcast: mensagem e conversa novas vão para a tela sem esperar a fila do Sidekiq
# - Outsider::EvolutionWatchdogJob: a cada minuto, reconecta instância da Evolution presa ou surda
#   (ver app/services/outsider/evolution_watchdog.rb)
# - Outsider::DeliveryCheckJob: a cada minuto e logo depois de cada envio, confere na Evolution se a
#   mensagem saiu para o WhatsApp e mostra ✓, ✓✓ ou falha (ver app/services/outsider/delivery_check.rb)
# - Outsider::EvolutionWebhooks: a Evolution recebe a mensagem certa e só os webhooks que ela usa
# Para tirar um agendamento: Sidekiq::Cron::Job.destroy('outsider_evolution_watchdog_job') ou
# Sidekiq::Cron::Job.destroy('outsider_delivery_check_job').
Rails.application.config.to_prepare do
  ActionCableListener.prepend(Outsider::InstantBroadcast) unless ActionCableListener < Outsider::InstantBroadcast
  WebhookListener.prepend(Outsider::EvolutionWebhooks) unless WebhookListener < Outsider::EvolutionWebhooks
  Webhooks::Trigger.prepend(Outsider::DeliveryWebhook) unless Webhooks::Trigger < Outsider::DeliveryWebhook
  Message.include(Outsider::DeliveryTracking) unless Message < Outsider::DeliveryTracking
  unless Api::V1::Accounts::Conversations::MessagesController < Outsider::DeliveryRetry
    Api::V1::Accounts::Conversations::MessagesController.prepend(Outsider::DeliveryRetry)
  end
end

Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_evolution_watchdog_job', cron: '* * * * *',
                              class: 'Outsider::EvolutionWatchdogJob', queue: 'scheduled_jobs')
    Sidekiq::Cron::Job.create(name: 'outsider_delivery_check_job', cron: '* * * * *',
                              class: 'Outsider::DeliveryCheckJob', queue: 'scheduled_jobs')
  end
end
