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
  # Entrega 26: URA por onde a ligação passou (ivr_data: opções escolhidas e dígitos digitados)
  belongs_to :ivr_flow, class_name: 'Outsider::Voice::IvrFlow', optional: true

  # gravação feita pelo telefone do navegador (Entrega 24), guardada pelo Active Storage (sem coluna nova)
  has_one_attached :recording
  # Entrega 26: recado deixado na URA (bloco Recado)
  has_one_attached :voicemail

  enum :direction, { inbound: 0, outbound: 1, internal: 2 }, validate: true
  enum :status, { ringing: 0, answered: 1, missed: 2, unanswered: 3, busy: 4, failed: 5 }, validate: true

  validates :linkedid, presence: true, uniqueness: true
  validates :started_at, presence: true

  scope :external, -> { where.not(direction: :internal) }
  scope :to_return, -> { inbound.missed.where(returned_at: nil) }

  # o que a tela mostra da URA (Entrega 26): o nome dela, por onde o cliente passou e o que ele digitou
  def ivr_summary
    ivr_data.slice('flow', 'path', 'vars').presence if ivr_data.present?
  end

  # número do cliente: quem ligou (recebida) ou para quem se ligou (feita)
  def customer_number
    inbound? ? from_number : to_number
  end
end
