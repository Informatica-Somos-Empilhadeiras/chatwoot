# OUTSIDER: o que as telas da área Teams recebem (lista, mensagens e avisos ao vivo).
module Outsider::Teams::Graph::Json
  module_function

  def thread(thread)
    {
      id: thread.id, kind: thread.kind, chat_type: thread.chat_type, title: thread.title, team_id: thread.team_id,
      team_name: thread.team_name, channel_id: thread.channel_id, members_count: Array(thread.members).size,
      last_message_preview: thread.last_message_preview, last_message_at: thread.last_message_at&.iso8601,
      unread_count: thread.unread_count, mention_count: thread.mention_count, last_read_at: thread.last_read_at&.iso8601,
      web_url: web_url(thread), peer_id: peer_id(thread), peer_photo: photo(thread.link, peer_id(thread))
    }
  end

  # no chat 1:1, a outra pessoa (para a bolinha de presença)
  def peer_id(thread)
    return nil unless thread.kind == 'chat' && thread.chat_type == 'oneOnOne'

    me = thread.link&.ms_user_id
    Array(thread.members).find { |member| member['id'].present? && member['id'] != me }&.dig('id')
  end

  # foto do perfil (Outsider::Teams::Graph::Photo): endereço assinado, nil sem id
  def photo(link, ms_id)
    Outsider::Teams::Graph::Photo.url(link, ms_id)
  end

  def message(message)
    {
      id: message.id, thread_id: message.thread_id, graph_id: message.graph_id, reply_to_graph_id: message.reply_to_graph_id,
      mine: message.mine, sender_name: message.sender_name, sender_ms_id: message.sender_ms_id,
      sender_photo: photo(message.thread&.link, message.sender_ms_id), subject: message.subject,
      content: message.content,
      quote: message.quote, mentions_me: message.mentions_me, status: message.status, error: message.error,
      sent_at: message.sent_at.iso8601, edited_at: message.edited_at&.iso8601, deleted: message.deleted_at.present?,
      attachments: attachments(message), reactions: reactions(message)
    }
  end

  # [{ emoji, count, mine, names }] na ordem em que apareceram
  def reactions(message)
    me = message.thread&.link&.ms_user_id
    Array(message.reactions).group_by { |item| item['type'] }.map do |emoji, items|
      { emoji: emoji, count: items.size, mine: items.any? { |item| me.present? && item['user_id'] == me },
        names: items.filter_map { |item| item['user_id'] == me ? 'Você' : item['name'] }.first(20) }
    end
  end

  # miniatura e download por endereço assinado (vale 12 horas); visualizar pede o endereço na hora (preview)
  def attachments(message)
    files = Outsider::Teams::Graph::Files
    Array(message.attachments).each_with_index.map do |attachment, index|
      ready = message.id.present? && !attachment['pending']
      kind = files.kind_of(attachment)
      {
        index: index, kind: kind, name: attachment['name'], size: attachment['size'],
        extension: files.extension(attachment['name']), source: attachment['source'],
        thumb_url: if ready
                     files.media_url(message, index, attachment['kind'] == 'image' ? 'image' : 'thumb')
                   end,
        download_url: ready ? files.media_url(message, index, 'download') : nil,
        audio_url: ready && kind == 'audio' ? files.media_url(message, index, 'audio') : nil,
        # visualizador: o vídeo e a foto inteira (a miniatura 'image' da Microsoft tem no máximo 800 px)
        video_url: ready && kind == 'video' ? files.media_url(message, index, 'video') : nil,
        full_url: if ready && kind == 'image'
                    files.media_url(message, index, attachment['hosted'].present? ? 'image' : 'full')
                  end,
        edit_url: edit_url(attachment),
        # transcrição feita no navegador (Outsider::Transcricao)
        transcript: attachment['transcript'].presence, transcript_meta: attachment['transcript_meta']
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
      id: link.id, user_id: link.user_id, photo: photo(link, link.ms_user_id), user_name: link.user&.name,
      display_name: link.display_name, email: link.email,
      status: link.status, last_error: link.last_error, sync_chats: link.sync_chats, channels: link.channel_list,
      all_channels: link.all_channels, hidden_channels: Array(link.hidden_channels), history_at: link.history_at&.iso8601,
      channel_view: link.channel_view,
      # entrou com permissões antigas: as novidades (presença, agenda, mencionar todos) pedem entrar de novo
      scope_outdated: link.scope_version < Outsider::Teams::Graph::Login::SCOPE_VERSION,
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
