# OUTSIDER: uma URA da Telefonia (Entrega 26). graph = { 'nodes', 'edges' } (ver Outsider::Voice::IvrGraph).
# numbers: os números (DDD + número) em que ela atende; vazio = todos os números que não têm URA própria. Cada
# número fica com uma URA ativa só, e só uma URA ativa pode atender "todos".
# audios: os áudios enviados para os blocos (o bloco guarda só o id do arquivo); os que nenhum bloco usa saem
# depois de salvar, como os arquivos do bot (Outsider::Bot::Flow).
class Outsider::Voice::IvrFlow < ApplicationRecord
  self.table_name = 'outsider_voice_ivr_flows'

  MAX_AUDIO = 10.megabytes

  belongs_to :account
  has_many_attached :audios, dependent: false

  before_validation :clean
  validates :name, presence: true, length: { maximum: 120 }
  validate :numbers_free, if: :active?
  after_save_commit :release_unused_audios, if: :saved_change_to_graph?
  before_destroy :release_all_audios, prepend: true

  scope :active, -> { where(active: true) }

  # a URA que atende este número: a do número ou, sem ela, a de todos os números
  def self.for_number(account, number)
    flows = where(account_id: account.id).active.to_a
    flows.find { |flow| flow.numbers.any? { |item| Outsider::Voice::PhoneNumber.same?(item, number) } } || flows.find { |flow| flow.numbers.empty? }
  end

  def graph_object
    @graph_object = nil if @graph_source != graph
    @graph_source = graph
    @graph_object ||= Outsider::Voice::IvrGraph.new(graph)
  end

  # pelos anexos já carregados (with_attached_audios), sem uma consulta por bloco
  def audio_blob(blob_id)
    id = blob_id.to_i
    audios_attachments.find { |attachment| attachment.blob_id == id }&.blob if id.positive?
  end

  def release_unused_audios(older_than: 1.hour)
    used = graph_object.prompts.filter_map { |prompt| prompt['audio_id'] }
    audios_attachments.where.not(blob_id: used).where(created_at: ...older_than.ago).find_each do |attachment|
      Outsider::Bot::Flow.release(attachment)
    end
  end

  private

  def clean
    self.graph = Outsider::Voice::IvrGraph.sanitize(graph)
    self.numbers = Array(numbers).filter_map do |number|
      Outsider::Voice::PhoneNumber.national(number)
    end.uniq.first(Outsider::Voice::Settings::MAX_NUMBERS)
  end

  def numbers_free
    others = self.class.where(account_id: account_id).active.where.not(id: id).to_a
    taken = others.flat_map(&:numbers)
    errors.add(:numbers, :taken) if numbers.any? { |number| taken.any? { |other| Outsider::Voice::PhoneNumber.same?(number, other) } }
    errors.add(:numbers, :all_taken) if numbers.empty? && others.any? { |flow| flow.numbers.empty? }
  end

  def release_all_audios
    audios_attachments.each { |attachment| Outsider::Bot::Flow.release(attachment) }
  end
end
