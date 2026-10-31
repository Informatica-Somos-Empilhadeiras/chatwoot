# OUTSIDER: de madrugada, apaga o registro de chamadas do bot com mais de 7 dias e as linhas de planilha de
# envios que não terminaram (o navegador fechou no meio) e os arquivos que nenhum bloco usa mais, para o
# banco e o disco não crescerem à toa.
class Outsider::Bot::LogCleanupJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH = 5000

  def perform
    loop do
      ids = Outsider::Bot::Log.where('created_at < ?', Outsider::Bot::Log::RETENTION.ago).limit(BATCH).pluck(:id)
      break if ids.empty?

      Outsider::Bot::Log.where(id: ids).delete_all
    end
    Outsider::Bot::Dataset.where('updated_at < ?', 1.day.ago).find_each do |dataset|
      dataset.all_rows.where.not(generation: dataset.generation).in_batches(of: BATCH).delete_all
    end
    # arquivos de Enviar arquivo que ficaram sem bloco (enviados e não salvos, ou bloco apagado)
    Outsider::Bot::Flow.joins(:files_attachments).distinct.find_each { |flow| flow.release_unused_files(older_than: 1.day) }
  end
end
