// OUTSIDER: o que o chat e o canal abertos na área Teams têm em comum: carregar as mensagens (e as
// anteriores), mandar, tentar de novo e receber os avisos ao vivo só desta conversa.
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import { TEAMS_NOTICE } from './teamsStore';
import { errorText } from './helpers';

export const useTeamsThread = (
  thread,
  { onLoaded, onIncoming, mode = null } = {}
) => {
  const { t } = useI18n();
  const items = ref([]);
  const more = ref(false);
  const isLoading = ref(true);
  const isLoadingOlder = ref(false);

  const load = async () => {
    isLoading.value = true;
    try {
      const { data } = await TeamsGraphAPI.messages(thread.id, { mode });
      items.value = data.payload;
      more.value = data.more;
      onLoaded?.();
    } catch (error) {
      useAlert(errorText(error, t));
    } finally {
      isLoading.value = false;
    }
  };

  const loadOlder = async () => {
    if (!items.value.length || isLoadingOlder.value) return;
    isLoadingOlder.value = true;
    try {
      const { data } = await TeamsGraphAPI.messages(thread.id, {
        before: items.value[0].id,
        mode,
      });
      items.value = [...data.payload, ...items.value];
      more.value = data.more;
    } catch (error) {
      useAlert(errorText(error, t));
    } finally {
      isLoadingOlder.value = false;
    }
  };

  const send = async payload => {
    try {
      const { data } = await TeamsGraphAPI.send(thread.id, payload);
      return data;
    } catch (error) {
      useAlert(errorText(error, t));
      return null;
    }
  };

  const retry = async message => {
    try {
      const { data } = await TeamsGraphAPI.retry(thread.id, message.id);
      Object.assign(message, data);
    } catch (error) {
      useAlert(errorText(error, t));
    }
  };

  const onNotice = data => {
    if (data?.kind !== 'teams' || data.thread?.id !== thread.id) return;
    if (data.message) onIncoming?.(data.message, data.action);
  };

  onMounted(() => {
    load();
    emitter.on(TEAMS_NOTICE, onNotice);
    emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, load);
  });

  onBeforeUnmount(() => {
    emitter.off(TEAMS_NOTICE, onNotice);
    emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, load);
  });

  return {
    items,
    more,
    isLoading,
    isLoadingOlder,
    load,
    loadOlder,
    send,
    retry,
  };
};
