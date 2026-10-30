# OUTSIDER: onde uma conversa está num fluxo do bot.
# status: active (o bot está conversando), finished (chegou ao fim), handed_off (passou para a equipe),
# cancelled (um agente assumiu ou a conversa foi resolvida) e expired (o cliente não respondeu a tempo).
# waiting: o que o bot espera agora ({ 'type' => 'menu' | 'question' | 'delay', 'attempts' => 0 }).
class Outsider::Bot::Session < ApplicationRecord
  belongs_to :account
  belongs_to :flow, class_name: 'Outsider::Bot::Flow'
  belongs_to :conversation

  enum :status, { active: 0, finished: 1, handed_off: 2, cancelled: 3, expired: 4 }, validate: true

  def expired_by_time?
    expires_at.present? && expires_at < Time.current
  end
end
