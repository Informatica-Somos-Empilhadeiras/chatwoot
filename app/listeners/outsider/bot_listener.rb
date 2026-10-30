# OUTSIDER: liga o bot aos eventos do Chatwoot (incluído no AsyncDispatcher pelo
# config/initializers/outsider_bot.rb, roda no Sidekiq).
# - mensagem do cliente: roda o fluxo (Outsider::Bot::RunJob)
# - agente respondeu, conversa atribuída a alguém ou resolvida: o bot para naquela conversa
class Outsider::BotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless any_flow?(account)

    if message.incoming? && !message.private?
      Outsider::Bot::RunJob.perform_later(message.id)
    elsif message.outgoing? && !message.private? && message.sender_type == 'User'
      stop(message.conversation)
    end
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    return unless any_flow?(account) && conversation.assignee_id.present?

    stop(conversation)
  end

  def conversation_status_changed(event)
    conversation, account = extract_conversation_and_account(event)
    return unless any_flow?(account) && conversation.resolved?

    stop(conversation, reopen: false)
  end

  private

  def any_flow?(account)
    Outsider::Bot::Flow.where(account_id: account.id).active.exists?
  end

  def stop(conversation, reopen: true)
    session = Outsider::Bot::Session.find_by(conversation_id: conversation.id, status: :active)
    Outsider::Bot::Runner.new(conversation).cancel(session, reopen: reopen) if session
  end
end
