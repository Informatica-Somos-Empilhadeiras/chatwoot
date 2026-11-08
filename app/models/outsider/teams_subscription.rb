# OUTSIDER: um aviso de mensagens novas pedido à Microsoft (assinatura do Microsoft Graph) para uma ligação do
# "Conectar meu Teams": kind 'chats' (todos os chats da pessoa) ou 'channel' (um canal escolhido). Vale no máximo 3 dias:
# o Outsider::Teams::Graph::RenewJob renova. client_state confere que o aviso é desta assinatura.
class Outsider::TeamsSubscription < ApplicationRecord
  self.table_name = 'outsider_teams_subscriptions'

  KINDS = %w[chats channel].freeze

  belongs_to :link, class_name: 'Outsider::TeamsLink', inverse_of: :subscriptions

  validates :kind, inclusion: { in: KINDS }
  validates :resource, :client_state, presence: true

  before_validation { self.client_state ||= SecureRandom.alphanumeric(48) }
end
