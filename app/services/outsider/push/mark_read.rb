# OUTSIDER: deixa lida a conversa (ou o chat do Teams) a partir do aviso: botão "Marcar como lida" e resposta rápida.
module Outsider::Push::MarkRead
  module_function

  def conversation(user, conversation)
    now = Time.current
    Notification::MarkConversationReadService.new(user: user, account: conversation.account, conversation: conversation).perform
    updates = { agent_last_seen_at: now }
    updates[:assignee_last_seen_at] = now if conversation.assignee_id == user.id
    conversation.update_columns(updates) # rubocop:disable Rails/SkipsModelValidations
    Conversations::UnreadCounts::Notifier.new(conversation).perform
  end

  def teams(thread)
    thread.update!(unread_count: 0, mention_count: 0, last_read_at: Time.current)
    Outsider::Teams::Graph::Notifier.changed(thread.link)
  end
end
