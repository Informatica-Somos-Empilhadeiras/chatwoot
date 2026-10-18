# OUTSIDER: aba "Grupos" na lista de conversas.
#
# Conversas de grupo do WhatsApp (Evolution API) têm o contato com
# identifier terminando em "@g.us". Este módulo é encaixado no
# ConversationFinder (ver config/initializers/outsider_group_conversations.rb)
# sem editar o arquivo original, para reduzir conflitos com o upstream.
#
# - assignee_type=group devolve só conversas de grupo
# - as abas em TABS_WITHOUT_GROUPS (Minhas/Esperando) não mostram grupos
# - "Todos" continua mostrando tudo
# - a resposta ganha count[:group_count]
module Outsider::GroupConversations
  GROUP_ASSIGNEE_TYPE = 'group'.freeze
  GROUP_IDENTIFIER_SUFFIX = '@g.us'.freeze
  TABS_WITHOUT_GROUPS = %w[me unassigned].freeze

  def perform
    with_group_count(super)
  end

  def perform_meta_only
    with_group_count(super)
  end

  private

  def with_group_count(result)
    result[:count][:group_count] = @outsider_group_count || 0
    result
  end

  # mine/unassigned sem grupos, all com grupos
  def set_count_for_all_conversations
    all_conversations = @conversations
    @outsider_group_count = only_group_conversations(all_conversations).unscope(:order).count

    @conversations = without_group_conversations(all_conversations)
    mine_count, unassigned_count, non_group_count = super
    @conversations = all_conversations

    [mine_count, unassigned_count, non_group_count + @outsider_group_count]
  end

  def filter_by_assignee_type
    return @conversations = only_group_conversations(@conversations) if @assignee_type == GROUP_ASSIGNEE_TYPE

    super
    @conversations = without_group_conversations(@conversations) if TABS_WITHOUT_GROUPS.include?(@assignee_type)
    @conversations
  end

  def group_contact_ids
    current_account.contacts.where(Contact.arel_table[:identifier].matches("%#{GROUP_IDENTIFIER_SUFFIX}")).select(:id)
  end

  def only_group_conversations(scope)
    scope.where(contact_id: group_contact_ids)
  end

  def without_group_conversations(scope)
    scope.where.not(contact_id: group_contact_ids)
  end
end
