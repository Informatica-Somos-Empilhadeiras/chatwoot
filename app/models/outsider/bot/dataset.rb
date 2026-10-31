# OUTSIDER: uma planilha enviada em Configurações > Automação por bot > Planilhas (Excel ou CSV, lida no
# navegador de quem envia). As linhas ficam em outsider_bot_dataset_rows, com índice, e o bloco Planilha
# procura nelas sem abrir arquivo nenhum.
#
# columns = [{ 'key' => 'modelo', 'label' => 'Modelo' }]: a chave vira {{linha.modelo}} no fluxo.
# generation: as linhas de um envio novo entram com outro número e só passam a valer no fim do envio
# (o bot continua usando as antigas enquanto isso).
class Outsider::Bot::Dataset < ApplicationRecord
  MAX_ROWS = 100_000
  MAX_COLUMNS = 60
  MAX_CELL = 1000
  CHUNK_ROWS = 2000

  belongs_to :account
  has_many :all_rows, class_name: 'Outsider::Bot::DatasetRow', dependent: :delete_all, inverse_of: :dataset

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :account_id, case_sensitive: false }

  before_validation { self.name = name.to_s.squish }

  def rows
    all_rows.where(generation: generation)
  end

  def column_keys
    Array(columns).pluck('key')
  end

  def api_json
    { id: id, name: name, columns: columns, rows_count: rows_count, file_name: file_name, updated_at: updated_at.to_i }
  end

  # rótulos do cabeçalho da planilha -> colunas com chave única, sem acento e sem espaço
  def self.build_columns(labels)
    seen = Hash.new(0)
    Array(labels).first(MAX_COLUMNS).each_with_index.map do |label, index|
      label = label.to_s.squish.first(80).presence || "Coluna #{index + 1}"
      key = ActiveSupport::Inflector.transliterate(label, '').downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '').first(40)
      key = "coluna_#{index + 1}" if key.blank?
      seen[key] += 1
      { 'key' => seen[key] > 1 ? "#{key}_#{seen[key]}" : key, 'label' => label }
    end
  end
end
