# OUTSIDER: manda o aviso novo (push) fora do caminho da mensagem. kind: customer (mensagem de cliente), teams (mensagem
# do Teams), notice (atribuição e citação do Chatwoot) ou missed_call (ligação perdida da Telefonia).
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
    when 'missed_call'
      call = Outsider::Voice::Call.find_by(id: id)
      Outsider::Push::MissedCall.new(call).perform if call
    end
  end
end
