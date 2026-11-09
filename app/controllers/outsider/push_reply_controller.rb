# OUTSIDER: "Envie uma resposta rápida" dentro do aviso novo. Igual ao "Marcar como lida": o service worker não tem a
# sessão da pessoa, então manda o token assinado de resposta que veio no aviso (vale 7 dias, só para aquela pessoa e
# aquela conversa ou chat do Teams). A resposta sai em nome da pessoa, como se ela tivesse escrito no Chatwoot, e a
# conversa fica lida.
class Outsider::PushReplyController < ActionController::API
  MAX_TEXT = 4000

  def create
    data = Outsider::Push.reply_data(params[:token])
    return head :unauthorized unless data.is_a?(Hash)

    user = User.find_by(id: data['u'])
    text = params[:text].to_s.strip.first(MAX_TEXT)
    return head :not_found unless user
    return head :unprocessable_entity if text.blank?

    sent = data['t'] ? reply_teams(user, data, text) : reply_conversation(user, data['c'], text)
    sent ? head(:created) : head(:forbidden)
  end

  private

  def reply_conversation(user, conversation_id, text)
    conversation = Conversation.find_by(id: conversation_id)
    return false unless conversation && allowed?(user, conversation)

    Current.user = user
    Messages::MessageBuilder.new(user, conversation, { content: text, private: false }).perform
    Outsider::Push::MarkRead.conversation(user, conversation)
    true
  ensure
    Current.reset
  end

  # quem pode escrever na conversa: administrador da conta ou agente da caixa
  def allowed?(user, conversation)
    account_user = user.account_users.find_by(account_id: conversation.account_id)
    return false unless account_user

    account_user.administrator? || conversation.inbox.members.exists?(id: user.id)
  end

  def reply_teams(user, data, text)
    thread = Outsider::TeamsThread.joins(:link).find_by(id: data['t'], outsider_teams_links: { user_id: user.id })
    return false unless thread && thread.link.status == 'active'

    link = thread.link
    message = thread.messages.create!(mine: true, sender_name: link.display_name || user.name, sender_ms_id: link.ms_user_id,
                                      content: text, reply_to_graph_id: thread.kind == 'channel' ? data['p'] : nil,
                                      status: 'sending', sent_at: Time.current)
    Outsider::Teams::Graph::Notifier.message(link, thread, message)
    Outsider::Teams::Graph::SendJob.perform_later(message.id)
    Outsider::Push::MarkRead.teams(thread)
    true
  end
end
