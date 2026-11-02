# OUTSIDER: registro de monitoria de ligação (Entrega 26): quem ouviu em silêncio (mode listen, o "modo fantasma")
# ou entrou sussurrando (mode whisper) na ligação de outra pessoa, de quando a quando. kind: supervisor (gestor da
# unidade ou administrador) ou guest (colega convidado pelo atendente). opened_at: quando o sussurro passou a ser
# ouvido também pelo cliente. Nasce quando a central pergunta se pode (Outsider::Voice::MonitorAccess) e termina
# no fim da ligação de quem monitora. Nunca aparece para o atendente monitorado.
class Outsider::Voice::Monitor < ApplicationRecord
  self.table_name = 'outsider_voice_monitors'

  MODES = %w[listen whisper].freeze
  KINDS = %w[supervisor guest].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :target_user, class_name: 'User'
  belongs_to :call, class_name: 'Outsider::Voice::Call', optional: true

  validates :linkedid, presence: true, uniqueness: true
  validates :mode, inclusion: { in: MODES }
  validates :kind, inclusion: { in: KINDS }
  validates :started_at, presence: true

  scope :running, -> { where(ended_at: nil).where(started_at: Outsider::Voice::Wallboard::LIVE_WINDOW.ago..) }
end
