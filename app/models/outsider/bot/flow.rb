# OUTSIDER: um fluxo do bot. graph = { 'nodes' => [...], 'edges' => [...] } (ver Outsider::Bot::Graph).
# inbox_ids vazio = todas as caixas da conta.
# files: os arquivos dos blocos Enviar arquivo, guardados uma vez; o bloco guarda só o blob_id e cada envio
# usa o mesmo arquivo (a mensagem da conversa aponta para ele, sem cópia). A cópia de um fluxo usa os mesmos.
class Outsider::Bot::Flow < ApplicationRecord
  belongs_to :account
  has_many :sessions, class_name: 'Outsider::Bot::Session', dependent: :delete_all
  has_many_attached :files, dependent: false
  before_destroy :release_all_files, prepend: true
  after_save_commit :release_unused_files, if: :saved_change_to_graph?

  validates :name, presence: true, length: { maximum: 120 }

  scope :active, -> { where(active: true) }

  before_validation { self.graph = Outsider::Bot::Graph.sanitize(graph) }

  def graph_object
    @graph_object = nil if @graph_source != graph
    @graph_source = graph
    @graph_object ||= Outsider::Bot::Graph.new(graph)
  end

  def runs_in?(inbox_id)
    ids = Array(inbox_ids).map(&:to_i)
    ids.empty? || ids.include?(inbox_id.to_i)
  end

  def file_blob(blob_id)
    files_blobs.find_by(id: blob_id.to_i) if blob_id.to_i.positive?
  end

  def used_blob_ids
    Array(graph['nodes']).filter_map { |node| node.dig('data', 'file', 'blob_id').to_i if node['type'] == 'file_send' }
  end

  # tira do fluxo os arquivos que nenhum bloco usa; os enviados há pouco ficam (o bloco pode ainda não ter
  # sido salvo). O arquivo só é apagado quando nada mais aponta para ele (cópia do fluxo, mensagem enviada).
  def release_unused_files(older_than: 1.hour)
    files_attachments.where.not(blob_id: used_blob_ids).where(created_at: ...older_than.ago).find_each do |attachment|
      self.class.release(attachment)
    end
  end

  def self.release(attachment)
    blob = attachment.blob
    attachment.delete
    blob.purge_later if blob && !ActiveStorage::Attachment.exists?(blob_id: blob.id)
  end

  private

  def release_all_files
    files_attachments.each { |attachment| self.class.release(attachment) }
  end
end
