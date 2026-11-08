# OUTSIDER: uma linha da área Teams de um colaborador: um chat (kind 'chat': 1:1, grupo ou chat de reunião) ou um canal
# de uma equipe (kind 'channel'). Guarda o resumo para a lista (última mensagem, não lidas) e os participantes do chat.
class Outsider::TeamsThread < ApplicationRecord
  self.table_name = 'outsider_teams_threads'

  KINDS = %w[chat channel].freeze

  belongs_to :link, class_name: 'Outsider::TeamsLink', inverse_of: :threads
  has_many :messages, class_name: 'Outsider::TeamsMessage', foreign_key: :thread_id, dependent: :destroy, inverse_of: :thread

  validates :kind, inclusion: { in: KINDS }
  validates :chat_id, presence: true, if: -> { kind == 'chat' }
  validates :team_id, :channel_id, presence: true, if: -> { kind == 'channel' }

  scope :chats, -> { where(kind: 'chat') }
  scope :channels, -> { where(kind: 'channel') }

  def channel?
    kind == 'channel'
  end
end
