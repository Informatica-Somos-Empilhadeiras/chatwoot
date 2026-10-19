# OUTSIDER: funil de vendas de uma unidade, com etapas configuráveis.
class Outsider::Crm::Pipeline < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  belongs_to :business_unit, class_name: 'Outsider::Crm::BusinessUnit'
  has_many :stages, -> { order(:position, :id) }, class_name: 'Outsider::Crm::Stage', dependent: :destroy, inverse_of: :pipeline
  has_many :opportunities, class_name: 'Outsider::Crm::Opportunity', dependent: :restrict_with_error

  accepts_nested_attributes_for :stages, allow_destroy: true

  validates :name, presence: true, length: { maximum: 255 }
  validates_same_account :business_unit
  validate :open_stage_present
  validate :removed_stages_unused

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def first_open_stage
    stages.find_by(kind: :open)
  end

  private

  def open_stage_present
    errors.add(:stages, :blank) if stages.reject(&:marked_for_destruction?).none?(&:kind_open?)
  end

  # Etapa com oportunidades não pode sair: mova as oportunidades antes
  def removed_stages_unused
    removed = stages.select(&:marked_for_destruction?).filter_map(&:id)
    return if removed.empty? || !Outsider::Crm::Opportunity.exists?(stage_id: removed)

    errors.add(:stages, :in_use, message: I18n.t('outsider_crm.errors.stage_in_use'))
  end
end
