# OUTSIDER: avisa ao vivo só o dono da área Teams (o canal pessoal dele no ActionCable, evento outsider.notice com
# kind 'teams'): mensagem nova ou mudada, e o total de não lidas para o número no menu.
module Outsider::Teams::Graph::Notifier
  module_function

  def message(link, thread, message, action: 'created')
    broadcast(link, action: "message_#{action}", thread: Outsider::Teams::Graph::Json.thread(thread),
                    message: Outsider::Teams::Graph::Json.message(message))
  end

  def changed(link)
    broadcast(link, action: 'changed')
  end

  def unread_total(link)
    link.threads.sum(:unread_count)
  end

  def broadcast(link, data)
    token = link.user&.pubsub_token
    return if token.blank?

    ActionCable.server.broadcast(token, { event: 'outsider.notice',
                                          data: data.merge(account_id: link.account_id, kind: 'teams', unread_total: unread_total(link)) })
  rescue StandardError => e
    Rails.logger.warn("[outsider_teams_graph] live update failed: #{e.message}")
  end
end
