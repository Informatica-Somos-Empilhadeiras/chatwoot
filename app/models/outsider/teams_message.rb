# OUTSIDER: uma mensagem da área Teams. mine = escrita pelo próprio colaborador (pelo Chatwoot ou pelo Teams). No canal,
# a publicação tem reply_to_graph_id vazio e as respostas apontam para ela. attachments: só nome, tamanho e onde está cada
# arquivo (OneDrive/SharePoint ou imagem colada no Teams); nada é gravado no Chatwoot (Outsider::Teams::Graph::Files).
# quote: a mensagem citada { graph_id, sender, text }. mentions_me: a mensagem chama a pessoa (@ela, @canal, @equipe).
# status: sending/sent/failed.
class Outsider::TeamsMessage < ApplicationRecord
  self.table_name = 'outsider_teams_messages'

  STATUSES = %w[sending sent failed].freeze

  belongs_to :thread, class_name: 'Outsider::TeamsThread', inverse_of: :messages

  validates :status, inclusion: { in: STATUSES }
  validates :sent_at, presence: true

  scope :posts, -> { where(reply_to_graph_id: nil) }
end
