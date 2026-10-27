# OUTSIDER: uma ligação da central de telefonia (Entrega 22). Nasce quando a central avisa o começo
# (Outsider::Voice::Router) e se completa com o atendimento e o fim (Outsider::Voice::CallEvents).
#
# status: ringing (tocando ou em andamento), answered (houve conversa), missed (recebida e ninguém atendeu),
# unanswered (feita e o cliente não atendeu), busy (ocupado) e failed (a operadora não completou).
# Recebida perdida fica na fila de retorno até alguém ligar de volta e o cliente atender (returned_at).
class Outsider::Voice::Call < ApplicationRecord
  self.table_name = 'outsider_voice_calls'

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :contact, optional: true
  belongs_to :opportunity, class_name: 'Outsider::Crm::Opportunity', optional: true
  belongs_to :task, class_name: 'Outsider::Crm::Task', optional: true
  belongs_to :returned_by, class_name: 'User', optional: true

  # gravação feita pelo telefone do navegador (Entrega 24), guardada pelo Active Storage (sem coluna nova)
  has_one_attached :recording

  enum :direction, { inbound: 0, outbound: 1, internal: 2 }, validate: true
  enum :status, { ringing: 0, answered: 1, missed: 2, unanswered: 3, busy: 4, failed: 5 }, validate: true

  validates :linkedid, presence: true, uniqueness: true
  validates :started_at, presence: true

  scope :external, -> { where.not(direction: :internal) }
  scope :to_return, -> { inbound.missed.where(returned_at: nil) }

  # número do cliente: quem ligou (recebida) ou para quem se ligou (feita)
  def customer_number
    inbound? ? from_number : to_number
  end
end
