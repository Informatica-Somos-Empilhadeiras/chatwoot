# OUTSIDER: pedido de um agente para receber uma conversa que está com outro (Outsider::ConversationTransfer).
#
# status: pending (esperando quem está com a conversa), accepted (a conversa passou para quem pediu),
# declined (recusado: fica na tela de quem pediu até ele clicar em OK, acknowledged_at), cancelled
# (quem pediu desistiu) e expired (a conversa mudou de agente por outro caminho antes da resposta).
class Outsider::TransferRequest < ApplicationRecord
  self.table_name = 'outsider_transfer_requests'

  belongs_to :account
  belongs_to :conversation
  belongs_to :requester, class_name: 'User'
  belongs_to :holder, class_name: 'User'

  enum :status, { pending: 0, accepted: 1, declined: 2, cancelled: 3, expired: 4 }, validate: true

  validates :note, length: { maximum: 500 }

  scope :unacknowledged, -> { where(acknowledged_at: nil) }

  # a conversa ainda está com quem recebeu o pedido
  def current?
    conversation.present? && conversation.assignee_id == holder_id
  end
end
