# OUTSIDER: um fluxo do bot. graph = { 'nodes' => [...], 'edges' => [...] } (ver Outsider::Bot::Graph).
# inbox_ids vazio = todas as caixas da conta.
class Outsider::Bot::Flow < ApplicationRecord
  belongs_to :account
  has_many :sessions, class_name: 'Outsider::Bot::Session', dependent: :delete_all

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
end
