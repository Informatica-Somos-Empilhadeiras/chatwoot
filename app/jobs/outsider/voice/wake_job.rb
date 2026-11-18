# OUTSIDER (técnicos): manda o push da ligação (ring), tira o aviso (stop, declined) ou avisa a perdida (missed) para quem foi
# acordado (Outsider::Voice::Wake). Fila critical: o celular precisa tocar enquanto a central segura a ligação.
class Outsider::Voice::WakeJob < ApplicationJob
  queue_as :critical

  def perform(account_id, linkedid, target, kind)
    account = Account.find_by(id: account_id)
    return unless account

    Outsider::Push::CallWake.new(account, linkedid, target).deliver(kind)
  end
end
