# OUTSIDER: oportunidade comercial de um contato do Chatwoot numa unidade. O contato nunca é
# copiado: nome e telefone vêm sempre de contacts.
class Outsider::Crm::Opportunity < ApplicationRecord
  include Outsider::Crm::AccountScoped
  include Outsider::Crm::OpportunityLifecycle
  include Outsider::Crm::OpportunityTimeline

  # Chave do pg_advisory_xact_lock que numera as oportunidades de cada conta
  DISPLAY_ID_LOCK = 7_210_420

  audited associated_with: :account, except: [:position]

  belongs_to :journey, class_name: 'Outsider::Crm::Journey'
  belongs_to :business_unit, class_name: 'Outsider::Crm::BusinessUnit'
  belongs_to :pipeline, class_name: 'Outsider::Crm::Pipeline'
  belongs_to :stage, class_name: 'Outsider::Crm::Stage'
  belongs_to :lost_reason, class_name: 'Outsider::Crm::LostReason', optional: true
  belongs_to :forwarded_from, class_name: 'Outsider::Crm::Opportunity', optional: true
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :tasks, class_name: 'Outsider::Crm::Task', dependent: :destroy
  has_many :activities, class_name: 'Outsider::Crm::Activity', dependent: :destroy

  enum :status, { open: 0, won: 1, lost: 2, forwarded: 3 }, validate: true

  validates :title, presence: true, length: { maximum: 255 }
  validates :value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :probability, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validates :currency, inclusion: { in: %w[BRL] }
  validates_same_account :journey, :business_unit, :pipeline, :stage, :lost_reason, :forwarded_from, :contact, :conversation
  validate :consistent_pipeline_and_stage
  validate :consistent_contact
  validate :owner_in_account
  validate :one_open_per_contact_and_unit, if: :open?
  validate :contact_not_group, on: :create
  validates_with Outsider::Crm::CustomFieldsValidator

  before_save :track_stage_change
  before_create :assign_display_id

  def code
    "OP-#{display_id}"
  end

  def effective_probability
    probability || stage&.probability
  end

  def value
    value_cents / 100.0
  end

  private

  def consistent_pipeline_and_stage
    errors.add(:pipeline, :invalid) if pipeline && pipeline.business_unit_id != business_unit_id
    errors.add(:stage, :invalid) if stage && stage.pipeline_id != pipeline_id
  end

  def consistent_contact
    errors.add(:journey, :invalid) if journey && journey.contact_id != contact_id
    errors.add(:conversation, :invalid) if conversation && conversation.contact_id != contact_id
  end

  def owner_in_account
    return if owner_id.blank? || account.blank?

    errors.add(:owner, :invalid) unless account.account_users.exists?(user_id: owner_id)
  end

  # O índice único parcial garante no banco; aqui só devolve um erro legível
  def one_open_per_contact_and_unit
    others = self.class.open.where(account_id: account_id, contact_id: contact_id, business_unit_id: business_unit_id)
    others = others.where.not(id: id) if persisted?
    errors.add(:base, :duplicate_open_opportunity, message: I18n.t('outsider_crm.errors.duplicate_open_opportunity')) if others.exists?
  end

  # Grupo do WhatsApp (identifier @g.us) não é cliente: não abre negócio
  def contact_not_group
    return unless contact && Outsider::Crm::ContactSummary.group?(contact)

    errors.add(:contact, :group_contact, message: I18n.t('outsider_crm.errors.group_contact'))
  end

  def assign_display_id
    self.class.connection.execute(
      self.class.sanitize_sql(['SELECT pg_advisory_xact_lock(?, ?)', DISPLAY_ID_LOCK, account_id])
    )
    self.display_id = self.class.where(account_id: account_id).maximum(:display_id).to_i + 1
  end

  def track_stage_change
    self.stage_changed_at = Time.current if new_record? || stage_id_changed?
  end
end
