# OUTSIDER: o que cada pessoa quer receber no aviso novo (push) e os nomes dos aparelhos dela. Sem linha = tudo ligado,
# menos "todas as mensagens dos chats em grupo do Teams". Ver app/services/outsider/push/.
class Outsider::PushSetting < ApplicationRecord
  self.table_name = 'outsider_push_settings'

  DEFAULTS = {
    'wa_assigned' => true,    # conversas atribuídas a mim
    'wa_unassigned' => true,  # conversas sem responsável nas minhas caixas
    'wa_groups' => true,      # grupos do WhatsApp (mesmas regras)
    'teams_chats' => true,    # chats 1:1 do Teams
    'teams_mentions' => true, # @menção em grupo ou canal
    'teams_replies' => true,  # respostas às publicações em que escrevi
    'teams_groups' => false,  # todas as mensagens dos chats em grupo
    'chatwoot' => true,       # conversa atribuída a mim e citação em nota privada
    'hide_content' => false   # esconder o texto na tela bloqueada
  }.freeze
  PERMISSIONS = %w[granted denied default unsupported].freeze

  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
  validates :permission, inclusion: { in: PERMISSIONS }, allow_nil: true

  def self.for(user, account)
    find_or_initialize_by(user_id: user.id, account_id: account.id)
  end

  # sem linha gravada: tudo no padrão
  def self.wants?(user, account, key)
    setting = find_by(user_id: user.id, account_id: account.id)
    setting ? setting.wants?(key) : DEFAULTS.fetch(key.to_s)
  end

  def self.device_key(endpoint)
    Digest::SHA256.hexdigest(endpoint.to_s).first(16)
  end

  def merged_prefs
    DEFAULTS.merge((prefs || {}).slice(*DEFAULTS.keys))
  end

  def wants?(key)
    merged_prefs.fetch(key.to_s)
  end
end
