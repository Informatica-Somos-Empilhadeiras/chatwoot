# OUTSIDER: registro de cada chamada que o bot faz a outro sistema (API, Nextcloud, banco) e de cada busca em
# planilha: bloco, tempo, resultado e erro, para descobrir rápido o que falhou (aba Registro). Fica 7 dias
# (Outsider::Bot::LogCleanupJob apaga o resto de madrugada).
#   kind   api | sheet | doc_search | doc_send | db_query | test
#   status ok | not_found | error
#   detail { method, url, request, response, error, test }, sem senha nenhuma
class Outsider::Bot::Log < ApplicationRecord
  RETENTION = 7.days
  EXCERPT = 2000

  belongs_to :account
  belongs_to :flow, class_name: 'Outsider::Bot::Flow', optional: true
  belongs_to :connection, class_name: 'Outsider::Bot::Connection', optional: true

  def self.record(**attributes)
    create!(attributes)
  rescue StandardError => e
    Rails.logger.warn("[Outsider::Bot::Log] não gravou o registro: #{e.class}: #{e.message}")
    nil
  end

  def self.excerpt(text)
    text = text.to_json unless text.is_a?(String) || text.nil?
    text.to_s.first(EXCERPT).presence
  end
end
