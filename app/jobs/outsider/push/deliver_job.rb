# OUTSIDER: manda o aviso novo (push) fora do caminho da mensagem. kind: customer (mensagem de cliente), teams (mensagem
# do Teams) ou notice (atribuição e citação do Chatwoot).
class Outsider::Push::DeliverJob < ApplicationJob
  queue_as :default

  def perform(kind, id)
    return unless Outsider::Push.enabled?

    case kind
    when 'customer'
      message = Message.find_by(id: id)
      Outsider::Push::CustomerMessage.new(message).perform if message
    when 'teams'
      message = Outsider::TeamsMessage.find_by(id: id)
      Outsider::Push::TeamsMessage.new(message).perform if message
    when 'notice'
      notification = Notification.find_by(id: id)
      Outsider::Push::ChatwootNotice.new(notification).perform if notification
    end
  end
end
