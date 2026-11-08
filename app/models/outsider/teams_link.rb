# OUTSIDER: o Teams de um colaborador ligado ao Chatwoot pelo login da conta Microsoft (Microsoft Graph, em nome dele).
# Os chats (1:1, grupos, reuniões) e os canais escolhidos chegam na área Teams só dele (Outsider::TeamsThread), fora das
# conversas do atendimento, e as respostas saem no Teams em nome dele. Tokens cifrados; status 'reconnect' quando a
# Microsoft não aceita mais o acesso (senha trocada, acesso revogado) e a pessoa precisa entrar de novo; 'disconnected'
# quando a pessoa (ou um administrador) desconecta: os avisos param, os tokens saem e as conversas já recebidas ficam.
class Outsider::TeamsLink < ApplicationRecord
  self.table_name = 'outsider_teams_links'

  STATUSES = %w[active reconnect disconnected].freeze

  belongs_to :account
  belongs_to :user
  has_many :subscriptions, class_name: 'Outsider::TeamsSubscription', foreign_key: :link_id, dependent: :delete_all,
                           inverse_of: :link
  has_many :threads, class_name: 'Outsider::TeamsThread', foreign_key: :link_id, dependent: :destroy, inverse_of: :link

  validates :ms_user_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :account_id }
  validates :ms_user_id, uniqueness: { scope: :account_id }

  scope :active, -> { where(status: 'active') }

  def graph_app
    Outsider::TeamsGraphApp.find_by(account_id: account_id)
  end

  def access_token
    Outsider::Teams::Secret.decrypt('graph_access_token', access_token_encrypted)
  end

  def access_token=(value)
    self.access_token_encrypted = Outsider::Teams::Secret.encrypt('graph_access_token', value)
  end

  def refresh_token
    Outsider::Teams::Secret.decrypt('graph_refresh_token', refresh_token_encrypted)
  end

  def refresh_token=(value)
    self.refresh_token_encrypted = Outsider::Teams::Secret.encrypt('graph_refresh_token', value) if value.present?
  end

  # [{ 'team_id', 'team_name', 'channel_id', 'channel_name' }]
  def channel_list
    Array(channels).map { |channel| channel.to_h.slice('team_id', 'team_name', 'channel_id', 'channel_name') }
  end
end
