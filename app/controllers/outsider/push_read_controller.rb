# OUTSIDER: botão "Marcar como lida" do aviso novo. O service worker não tem a sessão da pessoa, então manda o token
# assinado que veio no próprio aviso (vale 7 dias, só para aquela pessoa e aquela conversa ou chat do Teams).
class Outsider::PushReadController < ActionController::API
  def create
    data = Outsider::Push.read_data(params[:token])
    return head :unauthorized unless data.is_a?(Hash)

    user = User.find_by(id: data['u'])
    return head :not_found unless user

    data['t'] ? read_teams(user, data['t']) : read_conversation(user, data['c'])
    head :no_content
  end

  private

  def read_conversation(user, conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation && user.account_users.exists?(account_id: conversation.account_id)

    now = Time.current
    Notification::MarkConversationReadService.new(user: user, account: conversation.account, conversation: conversation).perform
    updates = { agent_last_seen_at: now }
    updates[:assignee_last_seen_at] = now if conversation.assignee_id == user.id
    conversation.update_columns(updates) # rubocop:disable Rails/SkipsModelValidations
    Conversations::UnreadCounts::Notifier.new(conversation).perform
  end

  def read_teams(user, thread_id)
    thread = Outsider::TeamsThread.joins(:link).find_by(id: thread_id, outsider_teams_links: { user_id: user.id })
    return unless thread

    thread.update!(unread_count: 0, mention_count: 0, last_read_at: Time.current)
    Outsider::Teams::Graph::Notifier.changed(thread.link)
  end
end
