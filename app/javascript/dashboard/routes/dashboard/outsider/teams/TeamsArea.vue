<script setup>
// OUTSIDER: a área Teams do menu (Chats e Canais do "Conectar meu Teams"). Fica fora de Conversas:
// nada daqui entra em Minhas, Esperando, Grupos ou Todas as conversas. Cada pessoa vê só o próprio
// Teams. À esquerda a lista (abas Chats e Canais); à direita o chat ou o canal aberto. No celular
// aparece uma coisa de cada vez. O canal abre no modo que a pessoa escolheu (Conversa, o padrão, ou
// Publicações); a escolha fica guardada na conexão dela.
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeamsLogo from './TeamsLogo.vue';
import TeamsList from './TeamsList.vue';
import TeamsChatView from './TeamsChatView.vue';
import TeamsChannelView from './TeamsChannelView.vue';
import { teamsState, TEAMS_NOTICE, TEAMS_ROUTE } from './teamsStore';
import { errorText } from './helpers';
import './teams.css';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const threads = ref([]);
const isLoading = ref(true);

const routeKind = computed(() =>
  route.params.kind === 'channels' ? 'channels' : 'chats'
);
const kind = computed(() =>
  routeKind.value === 'channels' ? 'channel' : 'chat'
);
const threadId = computed(() => Number(route.params.threadId) || null);
const selected = computed(
  () => threads.value.find(thread => thread.id === threadId.value) || null
);
const canWrite = computed(() => teamsState.status === 'active');
const channelView = computed(() =>
  teamsState.channelView === 'publicacoes' ? 'publicacoes' : 'conversa'
);

const changeView = mode => {
  const before = teamsState.channelView;
  teamsState.channelView = mode;
  TeamsGraphAPI.updateMe({ channel_view: mode }).catch(error => {
    teamsState.channelView = before;
    useAlert(errorText(error, t));
  });
};

const showConnect = computed(
  () => !isLoading.value && !teamsState.connected && !threads.value.length
);

const sortThreads = list =>
  [...list].sort((a, b) =>
    (b.last_message_at || '').localeCompare(a.last_message_at || '')
  );

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await TeamsGraphAPI.threads(kind.value);
    threads.value = sortThreads(data.payload);
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isLoading.value = false;
  }
};

const markRead = thread => {
  if (!thread?.unread_count && !thread?.mention_count) return;
  thread.unread_count = 0;
  thread.mention_count = 0;
  TeamsGraphAPI.read(thread.id).catch(() => {});
};

const open = thread =>
  router.push({
    name: TEAMS_ROUTE,
    params: { ...route.params, kind: routeKind.value, threadId: thread.id },
  });

const back = () =>
  router.push({
    name: TEAMS_ROUTE,
    params: { accountId: route.params.accountId, kind: routeKind.value },
  });

const goSettings = () =>
  router.push({
    name: 'outsider_teams_settings',
    params: { accountId: route.params.accountId },
  });

// aviso ao vivo: a linha da lista sobe com a última mensagem; a conversa aberta cuida da mensagem
const onNotice = data => {
  if (data?.kind !== 'teams' || !data.thread) return;
  if (data.thread.kind !== kind.value) return;
  const index = threads.value.findIndex(item => item.id === data.thread.id);
  const fresh = { ...data.thread };
  if (fresh.id === threadId.value && data.action === 'message_created') {
    fresh.unread_count = 0;
    fresh.mention_count = 0;
    TeamsGraphAPI.read(fresh.id).catch(() => {});
  }
  const list = [...threads.value];
  if (index >= 0) list.splice(index, 1, fresh);
  else list.push(fresh);
  threads.value = sortThreads(list);
};

watch(kind, load);
watch(selected, thread => markRead(thread), { immediate: true });

onMounted(() => {
  load();
  emitter.on(TEAMS_NOTICE, onNotice);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, load);
});

onBeforeUnmount(() => {
  emitter.off(TEAMS_NOTICE, onNotice);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, load);
});
</script>

<template>
  <section class="tms flex w-full h-full overflow-hidden bg-n-surface-1">
    <div
      v-if="showConnect"
      class="flex flex-col items-center justify-center flex-1 gap-3 p-8 text-center"
    >
      <span
        class="flex items-center justify-center size-16 rounded-2xl tms-soft"
      >
        <TeamsLogo :size="36" />
      </span>
      <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_AREA.CONNECT_TITLE') }}
      </h2>
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_TEAMS_AREA.CONNECT_TEXT') }}
      </p>
      <button
        type="button"
        class="px-4 py-2 text-sm font-semibold rounded-xl tms-accent-bg"
        @click="goSettings"
      >
        {{ t('OUTSIDER_TEAMS_AREA.CONNECT_BUTTON') }}
      </button>
    </div>

    <template v-else>
      <TeamsList
        :threads="threads"
        :kind="kind"
        :route-kind="routeKind"
        :selected-id="threadId"
        :is-loading="isLoading"
        :status="teamsState.status"
        :unread-chats="teamsState.unreadChats"
        :unread-channels="teamsState.unreadChannels"
        class="w-full md:w-[340px] shrink-0 border-r border-n-weak"
        :class="threadId ? 'hidden md:flex' : 'flex'"
        @open="open"
        @settings="goSettings"
      />
      <div
        class="flex-1 min-w-0"
        :class="threadId ? 'flex' : 'hidden md:flex'"
      >
        <TeamsChannelView
          v-if="
            selected &&
            selected.kind === 'channel' &&
            channelView === 'publicacoes'
          "
          :key="`posts-${selected.id}`"
          :thread="selected"
          :can-write="canWrite"
          @back="back"
          @change-view="changeView"
        />
        <TeamsChatView
          v-else-if="selected"
          :key="`${selected.kind}-${selected.id}`"
          :thread="selected"
          :can-write="canWrite"
          :channel-mode="selected.kind === 'channel'"
          @back="back"
          @change-view="changeView"
        />
        <div
          v-else
          class="flex flex-col items-center justify-center flex-1 gap-3 tms-bg text-n-slate-11"
        >
          <Spinner v-if="isLoading && threadId" :size="20" />
          <template v-else>
            <TeamsLogo :size="40" />
            <p class="mb-0 text-sm">
              {{
                kind === 'channel'
                  ? t('OUTSIDER_TEAMS_AREA.PICK_CHANNEL')
                  : t('OUTSIDER_TEAMS_AREA.PICK_CHAT')
              }}
            </p>
            <Button
              v-if="teamsState.status === 'reconnect'"
              sm
              amber
              faded
              icon="i-lucide-refresh-cw"
              :label="t('OUTSIDER_TEAMS_AREA.RECONNECT')"
              @click="goSettings"
            />
          </template>
        </div>
      </div>
    </template>
  </section>
</template>
