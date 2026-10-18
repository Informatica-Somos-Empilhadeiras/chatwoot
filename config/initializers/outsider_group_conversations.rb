# OUTSIDER: encaixa a aba "Grupos" no ConversationFinder (ver app/finders/outsider/group_conversations.rb)
Rails.application.config.to_prepare do
  ConversationFinder.prepend(Outsider::GroupConversations) unless ConversationFinder < Outsider::GroupConversations
end
