# OUTSIDER: modelo de proposta (venda ou locação). content guarda os textos padrão (abertura, condições,
# fechamento, quadro de assinatura) que a proposta nova recebe e pode editar, os blocos do conteúdo e o
# papel timbrado com elementos em posição livre (Outsider::Crm::ProposalTemplateLayout). Os dois modelos
# padrão (Outsider::Crm::ProposalTemplateDefaults) copiam as propostas da Somos e usam o papel timbrado que
# vem com o CRM até o administrador enviar outro cabeçalho e rodapé.
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
  # imagens dos elementos em posição livre (logo, selo...); o elemento guarda o id do anexo
  has_many_attached :layout_images
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

  def blocks
    Outsider::Crm::ProposalTemplateLayout.blocks(content)
  end

  def layout
    Outsider::Crm::ProposalTemplateLayout.layout(content)
  end

  # Anexos de imagem que nenhum elemento usa mais (sobra de imagem trocada ou elemento apagado)
  def unused_layout_images
    used = layout['elements'].filter_map { |element| element['image_id'] }
    layout_images.attachments.reject { |attachment| used.include?(attachment.id) }
  end

  private

  def normalize_content
    data = (content || {}).to_h.stringify_keys
    (TEXT_KEYS & data.keys).each { |key| data[key] = data[key].to_s }
    (FLAG_KEYS & data.keys).each { |key| data[key] = ActiveModel::Type::Boolean.new.cast(data[key]) || false }
    data['conditions'] = Outsider::Crm::Proposal.normalize_conditions(data['conditions'])
    self.content = normalize_design(data)
  end

  def normalize_design(data)
    data['validity_days'] = data['validity_days'].to_i if data.key?('validity_days')
    data['blocks'] = Outsider::Crm::ProposalTemplateLayout.normalize_blocks(data['blocks']) if data.key?('blocks')
    data['layout'] = Outsider::Crm::ProposalTemplateLayout.normalize_layout(data['layout']) if data.key?('layout')
    data
  end

  def valid_content
    errors.add(:content, :invalid) if TEXT_KEYS.any? { |key| content[key].to_s.length > 5_000 }
    errors.add(:content, :invalid) unless Outsider::Crm::Proposal.valid_conditions?(conditions)
    errors.add(:content, :invalid) if content.key?('blocks') && blocks.none? { |block| block['visible'] }
  end

  def valid_images
    [header_image, footer_image].select(&:attached?).map(&:blob).concat(layout_images.blobs.to_a).each do |blob|
      errors.add(:base, :invalid_image) unless IMAGE_TYPES.include?(blob.content_type)
      errors.add(:base, :image_too_large) if blob.byte_size > IMAGE_MAX_SIZE
    end
  end
end
