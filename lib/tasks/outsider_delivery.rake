# OUTSIDER: mostra, por caixa da Evolution, por que as mensagens estão (ou não) sendo conferidas: o que o
# Chatwoot e a Evolution têm de cada mensagem enviada. Só lê. Ver Outsider::DeliveryDiagnosis.
#   bin/rails outsider_delivery:diagnostico              # a última hora
#   bin/rails outsider_delivery:diagnostico MINUTOS=180
namespace :outsider_delivery do
  desc 'Retrato da conferência de entrega do WhatsApp (MINUTOS=60)'
  task diagnostico: :environment do
    Outsider::EvolutionApi.inboxes.each do |inbox|
      puts Outsider::DeliveryDiagnosis.new(inbox, minutes: ENV.fetch('MINUTOS', 60).to_i).lines
      puts
    end
  end
end
