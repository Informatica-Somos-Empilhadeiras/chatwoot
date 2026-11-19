# OUTSIDER: um envio do orçamento do ERP (Outsider::Erp::Budget) por WhatsApp ou e-mail. O PDF enviado fica ligado
# aqui; no WhatsApp a mensagem da conversa aponta para o mesmo arquivo (um blob só, como nas propostas do CRM).
class Outsider::Erp::BudgetSend < ApplicationRecord
  self.table_name = 'outsider_erp_budget_sends'

  belongs_to :account
  belongs_to :budget, class_name: 'Outsider::Erp::Budget', inverse_of: :sends
  belongs_to :user, optional: true

  has_one_attached :document

  enum :channel, { whatsapp: 0, email: 1 }, validate: true
  enum :status, { pending: 0, delivered: 1, failed: 2 }, validate: true

  validate { errors.add(:budget, :invalid) if budget && budget.account_id != account_id }
end
