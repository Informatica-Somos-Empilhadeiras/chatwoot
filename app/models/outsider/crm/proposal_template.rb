# OUTSIDER: modelo de proposta (venda ou locação). content guarda os textos padrão (abertura, condições,
# fechamento, quadro de assinatura) que a proposta nova recebe e pode editar; layout fica para o editor de
# modelos. Os dois modelos padrão (Outsider::Crm::ProposalDefaults) copiam as propostas da Somos e usam o
# papel timbrado que vem com o CRM até o administrador enviar outro cabeçalho e rodapé.
class Outsider::Crm::ProposalTemplate < ApplicationRecord
  include Outsider::Crm::AccountScoped

  IMAGE_TYPES = %w[image/png image/jpeg].freeze
  IMAGE_MAX_SIZE = 5.megabytes
  TEXT_KEYS = %w[intro title_prefix total_label parties_text acceptance_text closing signature_box
                 order_heading bank_heading documents_heading conditions_heading].freeze
  FLAG_KEYS = %w[show_discount show_parties show_bank show_specs].freeze

  audited associated_with: :account

  has_one_attached :header_image
  has_one_attached :footer_image
  has_many :proposals, class_name: 'Outsider::Crm::Proposal', foreign_key: :template_id, inverse_of: :template,
                       dependent: :restrict_with_error

  enum :kind, { sale: 0, rental: 1 }, validate: true

  validates :name, presence: true, length: { maximum: 255 }
  validate :valid_content
  validate :valid_images

  before_validation :normalize_content

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def text(key)
    content[key.to_s].to_s
  end

  def flag?(key)
    content[key.to_s] == true
  end

  def conditions
    Array(content['conditions'])
  end

  # Estilo das condições: 'table' (quadro com o nome à esquerda, como a venda) ou 'list' (lista com
  # marcadores, como a locação)
  def conditions_style
    content['conditions_style'] == 'list' ? 'list' : 'table'
  end

  def validity_days
    content['validity_days'].to_i.clamp(0, 365)
  end

  private

  def normalize_content
    data = (content || {}).to_h.stringify_keys
    (TEXT_KEYS & data.keys).each { |key| data[key] = data[key].to_s }
    (FLAG_KEYS & data.keys).each { |key| data[key] = ActiveModel::Type::Boolean.new.cast(data[key]) || false }
    data['conditions'] = Outsider::Crm::Proposal.normalize_conditions(data['conditions'])
    data['validity_days'] = data['validity_days'].to_i if data.key?('validity_days')
    self.content = data
  end

  def valid_content
    errors.add(:content, :invalid) if TEXT_KEYS.any? { |key| content[key].to_s.length > 5_000 }
    errors.add(:content, :invalid) unless Outsider::Crm::Proposal.valid_conditions?(conditions)
  end

  def valid_images
    [header_image, footer_image].each do |image|
      next unless image.attached?

      errors.add(image.name, :invalid) unless IMAGE_TYPES.include?(image.blob.content_type)
      errors.add(image.name, :too_long, count: IMAGE_MAX_SIZE) if image.blob.byte_size > IMAGE_MAX_SIZE
    end
  end
end
