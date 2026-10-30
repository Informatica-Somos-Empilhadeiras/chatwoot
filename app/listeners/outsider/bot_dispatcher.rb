# OUTSIDER: acrescenta o Outsider::BotListener aos ouvintes do AsyncDispatcher sem mexer no arquivo do Chatwoot.
module Outsider::BotDispatcher
  def listeners
    super + [Outsider::BotListener.instance]
  end
end
