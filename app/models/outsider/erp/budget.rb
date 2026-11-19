# OUTSIDER: orçamento de peças e serviços do ERP feito no chat (não confundir com a proposta comercial do CRM nem com
# o espelho dos orçamentos do ERP, Outsider::Erp::Quotes). Rascunho -> "Gravar no ERP" (Outsider::Erp::QuoteCreator)
# -> número oficial do Mais Prático. "imported" é o registro de um orçamento feito no próprio ERP, criado só para
# guardar os envios dele pelo chat. "submitting": a gravação está rodando (Outsider::Erp::BudgetSubmitJob).
#
# terms: condições (forma de pagamento, gênero, frete, vendedor, prazos, observações...), ver Outsider::Erp::BudgetForm.
# items: [{ codigo, descricao, unidade, tipo (0 peça, 1 serviço), ncm, quantidade, preco, desconto (%) }].
class Outsider::Erp::Budget < ApplicationRecord
  self.table_name = 'outsider_erp_budgets'
  # CodigoIntegracaoMobile do ERP (varchar 20): idempotência da gravação; "CW-" é das propostas antigas
  MOBILE_PREFIX = 'CWO-'.freeze
  # campo do relatório do ERP (Outsider::Erp::QuoteReport::HEADER) => condição do rascunho, onde o nome difere
  REPORT_TERMS = { 'icms_txt' => 'icms', 'ipi_txt' => 'ipi' }.freeze

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :user, optional: true
  has_many :sends, class_name: 'Outsider::Erp::BudgetSend', dependent: :destroy, inverse_of: :budget

  enum :status, { draft: 0, created: 1, imported: 2, submitting: 3 }, validate: true

  validates :company, presence: true, format: { with: Outsider::Erp::Sql::IDENT }
  validate :same_account

  scope :for_contact, ->(contact) { where(contact_id: contact.id) }

  def mobile_key = "#{MOBILE_PREFIX}#{id}"
  def in_erp? = erp_number.present?
  def services = items.select { |item| item['tipo'].to_i == 1 }
  def parts = items.reject { |item| item['tipo'].to_i == 1 }

  # total sem impostos (o ERP soma IPI/ST ao gravar): quantidade x preço menos o desconto de cada linha
  def self.line_total(item)
    gross = item['quantidade'].to_d * item['preco'].to_d
    (gross - (gross * item['desconto'].to_d / 100)).round(2)
  end

  def total = items.sum { |item| self.class.line_total(item) }

  # a conversa pelo número que a tela mostra (display_id), só se for deste contato
  def self.conversation_id_for(contact, display_id)
    return if display_id.blank? || contact.nil?

    contact.conversations.find_by(display_id: display_id)&.id
  end

  private

  def same_account
    errors.add(:contact, :invalid) if contact && contact.account_id != account_id
  end
end
