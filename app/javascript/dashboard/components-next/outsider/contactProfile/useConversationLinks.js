// OUTSIDER: links da conversa para "Mídia, links e docs". Junta os das mensagens já carregadas
// com os que a busca da conversa acha por "http" no servidor (as 30 mais novas com link), então
// aparecem links de mensagens antigas que ainda não foram carregadas na tela.
import { computed, reactive, watch } from 'vue';
import ConversationHistoryAPI from 'dashboard/api/outsider/conversationHistory';
import { linksFromMessages } from '../mediaViewer/mediaHelpers';

const fromServer = reactive({});

const load = async conversationId => {
  if (!conversationId || fromServer[conversationId]) return;
  fromServer[conversationId] = [];
  try {
    const { data } = await ConversationHistoryAPI.search(conversationId, {
      q: 'http',
    });
    fromServer[conversationId] = data.payload || [];
  } catch (error) {
    // sem a busca ficam só os links das mensagens carregadas
  }
};

export const useConversationLinks = chat => {
  watch(() => chat.value?.id, load, { immediate: true });
  return computed(() =>
    linksFromMessages([
      ...(chat.value?.messages || []),
      ...(fromServer[chat.value?.id] || []),
    ])
  );
};
