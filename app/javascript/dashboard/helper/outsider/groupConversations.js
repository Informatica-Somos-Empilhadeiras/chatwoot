// OUTSIDER: aba "Grupos" na lista de conversas.
// Conversas de grupo do WhatsApp (Evolution API) têm o contato com
// identifier terminando em "@g.us". O backend faz o mesmo filtro em
// app/finders/outsider/group_conversations.rb; aqui é para as conversas
// que chegam em tempo real caírem na aba certa.
import wootConstants from 'dashboard/constants/globals';

export const GROUP_IDENTIFIER_SUFFIX = '@g.us';

export const TABS_WITHOUT_GROUPS = [
  wootConstants.ASSIGNEE_TYPE.ME,
  wootConstants.ASSIGNEE_TYPE.UNASSIGNED,
];

export const isGroupConversation = conversation =>
  (conversation?.meta?.sender?.identifier || '').endsWith(
    GROUP_IDENTIFIER_SUFFIX
  );

export const filterByGroupTab = (shouldFilter, assigneeType, conversation) => {
  if (!shouldFilter) return false;
  if (assigneeType === wootConstants.ASSIGNEE_TYPE.GROUP) {
    return isGroupConversation(conversation);
  }
  if (TABS_WITHOUT_GROUPS.includes(assigneeType)) {
    return !isGroupConversation(conversation);
  }
  return true;
};
