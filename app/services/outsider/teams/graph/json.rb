# OUTSIDER: o que as telas da área Teams recebem (lista, mensagens e avisos ao vivo).
module Outsider::Teams::Graph::Json
  module_function

  def thread(thread)
    {
      id: thread.id, kind: thread.kind, chat_type: thread.chat_type, title: thread.title, team_id: thread.team_id,
      team_name: thread.team_name, channel_id: thread.channel_id, members_count: Array(thread.members).size,
      last_message_preview: thread.last_message_preview, last_message_at: thread.last_message_at&.iso8601,
      unread_count: thread.unread_count, mention_count: thread.mention_count, last_read_at: thread.last_read_at&.iso8601,
      web_url: web_url(thread)
    }
  end

  def message(message)
    {
      id: message.id, thread_id: message.thread_id, graph_id: message.graph_id, reply_to_graph_id: message.reply_to_graph_id,
      mine: message.mine, sender_name: message.sender_name, subject: message.subject, content: message.content,
      quote: message.quote, mentions_me: message.mentions_me, status: message.status, error: message.error,
      sent_at: message.sent_at.iso8601, edited_at: message.edited_at&.iso8601, deleted: message.deleted_at.present?,
      attachments: attachments(message)
    }
  end

  # miniatura e download por endereço assinado (vale 2 horas); visualizar pede o endereço na hora (preview)
  def attachments(message)
    files = Outsider::Teams::Graph::Files
    Array(message.attachments).each_with_index.map do |attachment, index|
      ready = message.id.present? && !attachment['pending']
      {
        index: index, kind: attachment['kind'], name: attachment['name'], size: attachment['size'],
        extension: files.extension(attachment['name']), source: attachment['source'],
        thumb_url: if ready
                     files.media_url(message, index, attachment['kind'] == 'image' ? 'image' : 'thumb')
                   end,
        download_url: ready ? files.media_url(message, index, 'download') : nil,
        edit_url: edit_url(attachment)
      }
    end
  end

  # abrir no Office/OneDrive para editar (imagem colada no Teams não tem)
  def edit_url(attachment)
    return nil if attachment['hosted'].present?

    attachment['web_url'].presence || attachment['url']
  end

  def link(link)
    return nil unless link

    {
      id: link.id, user_id: link.user_id, user_name: link.user&.name, display_name: link.display_name, email: link.email,
      status: link.status, last_error: link.last_error, sync_chats: link.sync_chats, channels: link.channel_list,
      all_channels: link.all_channels, hidden_channels: Array(link.hidden_channels), history_at: link.history_at&.iso8601,
      channel_view: link.channel_view,
      last_activity_at: link.last_activity_at&.iso8601, created_at: link.created_at.iso8601,
      subscriptions: link.subscriptions.map do |subscription|
        { kind: subscription.kind, channel_id: subscription.channel_id, ok: subscription.subscription_id.present? &&
          subscription.expires_at.present? && subscription.expires_at > Time.current, error: subscription.last_error,
          pending: subscription.subscription_id.blank? && subscription.last_error.blank? }
      end
    }
  end

  # abre a conversa no próprio Teams
  def web_url(thread)
    if thread.kind == 'chat'
      "https://teams.microsoft.com/l/chat/#{ERB::Util.url_encode(thread.chat_id)}/0"
    else
      "https://teams.microsoft.com/l/channel/#{ERB::Util.url_encode(thread.channel_id)}/#{ERB::Util.url_encode(thread.title.to_s)}" \
        "?groupId=#{ERB::Util.url_encode(thread.team_id)}"
    end
  end
end
