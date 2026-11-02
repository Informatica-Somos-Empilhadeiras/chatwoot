# OUTSIDER: acrescenta o Outsider::TeamsListener aos ouvintes do AsyncDispatcher sem mexer no arquivo do Chatwoot.
module Outsider::TeamsDispatcher
  def listeners
    super + [Outsider::TeamsListener.instance]
  end
end
