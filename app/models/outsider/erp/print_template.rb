# OUTSIDER: modelo de relatório (impressão) de OS ou de orçamento do ERP, montado no estúdio. O content (identidade
# visual, campos e blocos) é limpo por Outsider::Erp::Prints::Content antes de gravar; as imagens fixas (logo enviado,
# imagens soltas) ficam em images e cada bloco guarda o id do anexo. Os padrões (builtin) vêm de
# Outsider::Erp::Prints::Defaults; qual modelo cada tipo de atendimento usa fica em Outsider::Erp::Prints::Bindings.
class Outsider::Erp::PrintTemplate < ApplicationRecord
  self.table_name = 'outsider_erp_print_templates'
  KINDS = Outsider::Erp::Prints::Catalog::KINDS
  IMAGE_TYPES = %w[image/png image/jpeg].freeze
  IMAGE_MAX_SIZE = 5.megabytes
  MAX_PER_KIND = 40

  belongs_to :account
  has_many_attached :images

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 120 }
  validate :valid_images
  validate :within_limit, on: :create

  before_validation :normalize_content

  scope :ordered, -> { order(Arel.sql('builtin IS NULL'), :id) }

  def theme = content['theme']
  def blocks = content['blocks']
  def fields = content['fields']

  # anexos que nenhum bloco usa mais (logo trocado, imagem apagada)
  def unused_images
    used = Outsider::Erp::Prints::Content.image_ids(content)
    images.attachments.reject { |attachment| used.include?(attachment.id) }
  end

  def image_attachment(id)
    images.attachments.find { |attachment| attachment.id == id.to_i } if id.present?
  end

  private

  def normalize_content
    self.content = Outsider::Erp::Prints::Content.normalize(kind, content) if KINDS.include?(kind)
  end

  def valid_images
    images.blobs.each do |blob|
      errors.add(:base, :invalid_image) unless IMAGE_TYPES.include?(blob.content_type)
      errors.add(:base, :image_too_large) if blob.byte_size > IMAGE_MAX_SIZE
    end
  end

  def within_limit
    errors.add(:base, :too_many) if self.class.where(account_id: account_id, kind: kind).count >= MAX_PER_KIND
  end
end
