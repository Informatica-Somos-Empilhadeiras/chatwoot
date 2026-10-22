# OUTSIDER: máquina ou acessório do catálogo do CRM, usado nos itens das propostas. A imagem fica no
# armazenamento de arquivos do Chatwoot (Active Storage) uma vez só; as propostas apontam para o produto.
# Produto que já está numa proposta não se apaga (fica inativo), para a proposta continuar com a imagem.
class Outsider::Crm::Product < ApplicationRecord
  include Outsider::Crm::AccountScoped

  IMAGE_TYPES = %w[image/png image/jpeg].freeze
  IMAGE_MAX_SIZE = 5.megabytes
  MAX_SPECS = 40
  MAX_FEATURES = 60

  audited associated_with: :account

  has_one_attached :image
  has_many :proposal_items, class_name: 'Outsider::Crm::ProposalItem', dependent: :restrict_with_error

  enum :kind, { machine: 0, accessory: 1 }, validate: true

  validates :name, presence: true, length: { maximum: 255 }
  validates :code, :brand, length: { maximum: 120 }
  validates :description, length: { maximum: 5_000 }
  validates :sale_price_cents, :rental_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :valid_specs
  validate :valid_features
  validate :valid_image

  before_validation :normalize_lists

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }

  # Retrato do produto guardado no item da proposta: mudar o catálogo depois não muda proposta feita
  def details
    { 'title' => name, 'code' => code, 'brand' => brand, 'specs' => specs, 'features' => features }
  end

  private

  # specs: [{ label:, value:, bold: }]; features: ['Motor Xinchai C490 Diesel', ...]
  def normalize_lists
    self.specs = Array(specs).filter_map do |spec|
      spec = spec.to_h.stringify_keys
      label = spec['label'].to_s.strip
      next if label.blank?

      { 'label' => label, 'value' => spec['value'].to_s.strip, 'bold' => ActiveModel::Type::Boolean.new.cast(spec['bold']) || false }
    end
    self.features = Array(features).map { |feature| feature.to_s.strip }.compact_blank
  end

  def valid_specs
    errors.add(:specs, :too_long, count: MAX_SPECS) if specs.size > MAX_SPECS
    errors.add(:specs, :invalid) if specs.any? { |spec| spec['label'].length > 120 || spec['value'].length > 120 }
  end

  def valid_features
    errors.add(:features, :too_long, count: MAX_FEATURES) if features.size > MAX_FEATURES
    errors.add(:features, :invalid) if features.any? { |feature| feature.length > 200 }
  end

  def valid_image
    return unless image.attached?

    errors.add(:image, :invalid) unless IMAGE_TYPES.include?(image.blob.content_type)
    errors.add(:image, :too_long, count: IMAGE_MAX_SIZE) if image.blob.byte_size > IMAGE_MAX_SIZE
  end
end
