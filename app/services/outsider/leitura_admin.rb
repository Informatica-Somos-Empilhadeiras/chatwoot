# OUTSIDER: administrador abre uma conversa que não é dele sem marcá-la como lida.
#
# No Chatwoot, abrir uma conversa grava agent_last_seen_at, um campo único da
# conversa: o contador de "não lidas" some para TODA a equipe. Quando um
# administrador só está acompanhando (conversa de outro agente ou sem agente),
# isso apagava o aviso que o agente responsável ainda precisava ver.
#
# Encaixado em Api::V1::Accounts::ConversationsController#update_last_seen
# (config/initializers/outsider_leitura_admin.rb). As notificações do próprio
# administrador continuam sendo marcadas como lidas; só a conversa fica como
# estava. A resposta devolve a conversa sem alteração, e o painel usa o
# unread_count dela (store/modules/conversations/actions/messageReadActions.js).
#
# O administrador pode voltar ao comportamento padrão no Perfil
# (users.ui_settings['outsider_marcar_lida_outros'] = true) ou, numa conversa
# específica, usar "Marcar como lida" no menu da lista (param outsider_forcar).
module Outsider::LeituraAdmin
  SETTING = 'outsider_marcar_lida_outros'.freeze
  FORCE_PARAM = :outsider_forcar

  def self.preservar?(user, conversation)
    return false unless user.is_a?(User) && user.administrator?
    return false if marca_outros?(user)

    conversation.assignee_id != user.id
  end

  def self.marca_outros?(user)
    ActiveModel::Type::Boolean.new.cast(user.ui_settings.to_h[SETTING]) == true
  end

  def update_last_seen
    return super if ActiveModel::Type::Boolean.new.cast(params[FORCE_PARAM])
    return super unless Outsider::LeituraAdmin.preservar?(Current.user, @conversation)

    Notification::MarkConversationReadService.new(user: Current.user, account: Current.account, conversation: @conversation).perform
  end
end
