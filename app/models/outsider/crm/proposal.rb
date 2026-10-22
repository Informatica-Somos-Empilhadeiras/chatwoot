# OUTSIDER: proposta de venda ou locação para um contato do Chatwoot. Os dados da empresa do cliente
# (customer), as condições e a assinatura ficam guardados na proposta: mudar o contato, o modelo ou o
# catálogo depois não muda proposta feita. O negócio é opcional e nunca depende da proposta.
# O PDF é montado na hora a partir destes dados (Outsider::Crm::ProposalPdf); só o que é enviado ao
# cliente fica guardado (Entrega 15), um arquivo por versão enviada.
class Outsider::Crm::Proposal < ApplicationRecord
  include Outsider::Crm::AccountScoped

  # Chave do pg_advisory_xact_lock que numera as propostas de cada conta
  NUMBER_LOCK = 7_210_421
  CUSTOMER_KEYS = %w[company document state_registration address district city state zip phone email attention].freeze
  SIGNER_KEYS = %w[name title phone email].freeze
  MAX_CONDITIONS = 40
  MAX_ITEMS = 50

  audited associated_with: :account, except: [:total_cents]

  belongs_to :contact
  belongs_to :opportunity, class_name: 'Outsider::Crm::Opportunity', optional: true
  belongs_to :business_unit, class_name: 'Outsider::Crm::BusinessUnit', optional: true
  belongs_to :template, class_name: 'Outsider::Crm::ProposalTemplate'
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :items, -> { order(:position, :id) }, class_name: 'Outsider::Crm::ProposalItem', inverse_of: :proposal,
                                                 dependent: :destroy, autosave: true
  has_many :sends, class_name: 'Outsider::Crm::ProposalSend', dependent: :destroy

  enum :kind, { sale: 0, rental: 1 }, validate: true
  enum :status, { draft: 0, sent: 1, accepted: 2, rejected: 3, canceled: 4 }, validate: true

  validates :title, presence: true, length: { maximum: 255 }
  validates :notes, length: { maximum: 10_000 }
  validates :issued_on, presence: true
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: %w[BRL] }
  validates_same_account :contact, :opportunity, :business_unit, :template
  validate :consistent_opportunity
  validate :consistent_template
  validate :owner_in_account
  validate :valid_texts
  validate :contact_not_group, on: :create

  before_validation :normalize_texts
  before_create :assign_number

  def code
    "PROPOSTA #{number}"
  end

  # Vencida: passou da validade sem ser aceita, recusada nem cancelada
  def expired?
    (draft? || sent?) && valid_until.present? && valid_until < Time.zone.today
  end

  def display_status
    expired? ? 'expired' : status
  end

  def recalculate_total
    self.total_cents = items.reject(&:marked_for_destruction?).each(&:apply_total).sum(&:total_cents)
  end

  def self.normalize_conditions(list)
    Array(list).filter_map do |condition|
      condition = condition.to_h.stringify_keys
      label = condition['label'].to_s.strip
      text = condition['text'].to_s.strip
      next if label.blank? && text.blank?

      { 'label' => label, 'text' => text }
    end
  end

  def self.valid_conditions?(list)
    list.size <= MAX_CONDITIONS && list.all? { |condition| condition['label'].length <= 120 && condition['text'].length <= 5_000 }
  end

  private

  def normalize_texts
    self.customer = (customer || {}).to_h.stringify_keys.slice(*CUSTOMER_KEYS).transform_values { |value| value.to_s.strip }
    self.signer = (signer || {}).to_h.stringify_keys.slice(*SIGNER_KEYS).transform_values { |value| value.to_s.strip }
    self.conditions = self.class.normalize_conditions(conditions)
  end

  def valid_texts
    errors.add(:customer, :invalid) if customer.values.any? { |value| value.length > 500 }
    errors.add(:signer, :invalid) if signer.values.any? { |value| value.length > 255 }
    errors.add(:conditions, :invalid) unless self.class.valid_conditions?(conditions)
  end

  def consistent_opportunity
    errors.add(:opportunity, :invalid) if opportunity && opportunity.contact_id != contact_id
  end

  def consistent_template
    errors.add(:template, :invalid) if template && template.kind != kind
  end

  def owner_in_account
    return if owner_id.blank? || account.blank?

    errors.add(:owner, :invalid) unless account.account_users.exists?(user_id: owner_id)
  end

  # Grupo do WhatsApp (identifier @g.us) não é cliente
  def contact_not_group
    return unless contact && Outsider::Crm::ContactSummary.group?(contact)

    errors.add(:contact, :group_contact, message: I18n.t('outsider_crm.errors.group_contact'))
  end

  # Continua a numeração da empresa: o primeiro número pode ser definido nas configurações (próximo número)
  def assign_number
    self.class.connection.execute(self.class.sanitize_sql(['SELECT pg_advisory_xact_lock(?, ?)', NUMBER_LOCK, account_id]))
    last = self.class.where(account_id: account_id).maximum(:number).to_i
    self.number = [last + 1, Outsider::Crm::ProposalConfig.new(account).next_number].max
  end
end
