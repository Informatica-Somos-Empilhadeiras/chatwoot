# OUTSIDER: continua o fluxo depois da espera de um bloco Mensagem ("digitando..."), com a mesma trava
# por conversa do Outsider::Bot::RunJob.
class Outsider::Bot::ContinueJob < ApplicationJob
  queue_as :high

  def perform(session_id, node_id, attempt = 0)
    session = Outsider::Bot::Session.find_by(id: session_id)
    return unless session&.active? && session.conversation

    key = format(Outsider::Bot::RunJob::LOCK_KEY, conversation_id: session.conversation_id)
    lock_manager = Redis::LockManager.new
    unless lock_manager.lock(key, Outsider::Bot::RunJob::LOCK_TTL)
      self.class.set(wait: Outsider::Bot::RunJob::RETRY_IN).perform_later(session_id, node_id, attempt + 1) if attempt < 10
      return
    end

    begin
      Outsider::Bot::Runner.new(session.conversation).resume(session.reload, node_id)
    ensure
      lock_manager.unlock(key)
    end
  end
end
