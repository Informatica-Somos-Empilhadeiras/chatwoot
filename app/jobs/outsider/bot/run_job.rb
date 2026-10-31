# OUTSIDER: roda o bot para uma mensagem recebida (Outsider::Bot::Runner). Uma conversa por vez: se
# outra mensagem da mesma conversa ainda está sendo tratada, esta espera um pouco e tenta de novo (até
# uns 2 minutos, o tempo de algumas chamadas lentas a outros sistemas).
class Outsider::Bot::RunJob < ApplicationJob
  queue_as :high

  LOCK_KEY = 'OUTSIDER::BOT::CONVERSATION::%<conversation_id>d'.freeze
  LOCK_TTL = 3.minutes
  RETRY_IN = 3.seconds
  MAX_ATTEMPTS = 40

  def perform(message_id, attempt = 0)
    message = Message.find_by(id: message_id)
    return unless message&.conversation

    key = format(LOCK_KEY, conversation_id: message.conversation_id)
    unless lock_manager.lock(key, LOCK_TTL)
      self.class.set(wait: RETRY_IN).perform_later(message_id, attempt + 1) if attempt < MAX_ATTEMPTS
      return
    end

    begin
      Outsider::Bot::Runner.new(message.conversation).handle_incoming(message)
    ensure
      lock_manager.unlock(key)
    end
  end

  private

  def lock_manager
    @lock_manager ||= Redis::LockManager.new
  end
end
