<script setup>
// OUTSIDER: "Meu Teams" em Configurações > Microsoft Teams. Antes de conectar: um botão só, que leva
// para o login da Microsoft. Conectado: quem é, entrar de novo, desconectar e o que trazer para o
// Chatwoot (meus chats e os canais das minhas equipes).
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeamsLogo from './TeamsLogo.vue';
import { errorText } from './helpers';

const props = defineProps({ info: { type: Object, required: true } });
const emit = defineEmits(['changed']);

const { t } = useI18n();
const me = computed(() => props.info.me);
const connected = computed(
  () => me.value && me.value.status !== 'disconnected'
);
const isGoing = ref(false);
const isSaving = ref(false);
const isLoadingTeams = ref(false);
const directory = ref([]);
const syncChats = ref(true);
const allChannels = ref(true);
const chosen = ref(new Set());

const channelKey = (teamId, channelId) => `${teamId}|${channelId}`;

const directoryKeys = () =>
  directory.value.flatMap(team =>
    team.channels.map(channel => channelKey(team.team_id, channel.channel_id))
  );

// "Todos os canais": tudo marcado menos o que a pessoa desmarcou; senão, só os escolhidos
const fillChannels = () => {
  if (allChannels.value && directory.value.length) {
    const hidden = new Set(
      (me.value?.hidden_channels || []).map(c =>
        channelKey(c.team_id, c.channel_id)
      )
    );
    chosen.value = new Set(directoryKeys().filter(key => !hidden.has(key)));
    return;
  }
  chosen.value = new Set(
    (me.value?.channels || []).map(c => channelKey(c.team_id, c.channel_id))
  );
};

const fillChoices = () => {
  syncChats.value = me.value?.sync_chats ?? true;
  allChannels.value = me.value?.all_channels ?? true;
  fillChannels();
};

const setAllChannels = value => {
  allChannels.value = value;
  if (value) chosen.value = new Set(directoryKeys());
};

const savedTeams = () => {
  const teams = {};
  (me.value?.channels || []).forEach(channel => {
    teams[channel.team_id] ||= {
      team_id: channel.team_id,
      team_name: channel.team_name,
      channels: [],
    };
    teams[channel.team_id].channels.push({
      channel_id: channel.channel_id,
      channel_name: channel.channel_name,
    });
  });
  return Object.values(teams);
};

const loadDirectory = async (refresh = false) => {
  if (!connected.value || me.value.status !== 'active') return;
  isLoadingTeams.value = true;
  try {
    const { data } = await TeamsGraphAPI.directory(refresh);
    directory.value = data.payload;
    fillChannels();
  } catch (error) {
    // sem a Microsoft no momento: mostra ao menos os canais já escolhidos, para não parecer que sumiram
    directory.value = savedTeams();
    useAlert(errorText(error, t));
  } finally {
    isLoadingTeams.value = false;
  }
};

// só recarrega as escolhas quando elas mudam no servidor (a tela confere sozinha enquanto a Microsoft trabalha)
const choicesSignature = computed(() =>
  JSON.stringify([
    me.value?.status,
    me.value?.sync_chats,
    me.value?.all_channels,
    me.value?.channels,
    me.value?.hidden_channels,
  ])
);
watch(
  choicesSignature,
  () => {
    fillChoices();
    loadDirectory();
  },
  { immediate: true }
);

const toggle = (teamId, channelId) => {
  const key = channelKey(teamId, channelId);
  const next = new Set(chosen.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  chosen.value = next;
};

const signIn = async () => {
  isGoing.value = true;
  try {
    const { data } = await TeamsGraphAPI.authorizeUrl();
    window.location.assign(data.url);
  } catch (error) {
    isGoing.value = false;
    useAlert(errorText(error, t));
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    const channels = [...chosen.value].map(key => {
      const [team_id, channel_id] = key.split('|');
      return { team_id, channel_id };
    });
    await TeamsGraphAPI.updateMe({
      sync_chats: syncChats.value,
      all_channels: allChannels.value,
      channels,
    });
    useAlert(t('OUTSIDER_TEAMS_GRAPH.SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isSaving.value = false;
  }
};

const disconnect = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('OUTSIDER_TEAMS_GRAPH.DISCONNECT_CONFIRM'))) return;
  try {
    await TeamsGraphAPI.disconnect();
    emit('changed');
  } catch (error) {
    useAlert(errorText(error, t));
  }
};

const problems = computed(() =>
  (me.value?.subscriptions || []).filter(item => !item.ok && !item.pending)
);

// avisos da Microsoft sendo pedidos e mensagens antigas chegando (em segundo plano): a tela confere sozinha
const working = computed(
  () =>
    me.value?.status === 'active' &&
    ((me.value?.subscriptions || []).some(item => item.pending) ||
      (me.value?.sync_chats && !me.value?.history_at))
);
let pollTimer = null;
let polls = 0;
const schedulePoll = () => {
  clearTimeout(pollTimer);
  if (!working.value || polls >= 40) return;
  pollTimer = setTimeout(() => {
    polls += 1;
    emit('changed');
  }, 6000);
};
watch([working, me], schedulePoll, { immediate: true });
onBeforeUnmount(() => clearTimeout(pollTimer));
</script>

<template>
  <!-- ainda não conectado -->
  <section
    v-if="!connected"
    class="flex flex-col items-center p-6 text-center outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
    data-testid="teams-my-card"
  >
    <span class="flex items-center justify-center size-14 rounded-2xl tms-soft">
      <TeamsLogo :size="34" />
    </span>
    <h3 class="mt-3 mb-1 text-base font-semibold text-n-slate-12">
      {{ t('OUTSIDER_TEAMS_GRAPH.MY_TITLE') }}
    </h3>
    <template v-if="info.configured">
      <p class="max-w-sm mb-0 text-sm text-n-slate-11">
        {{
          me
            ? t('OUTSIDER_TEAMS_GRAPH.MY_DISCONNECTED')
            : t('OUTSIDER_TEAMS_GRAPH.MY_INTRO')
        }}
      </p>
      <button
        type="button"
        class="inline-flex items-center gap-3 px-5 py-2.5 mt-4 text-[15px] font-semibold border-[1.5px] rounded-md border-n-slate-8 bg-white text-[#1c2024] hover:bg-[#f6f6f6] disabled:opacity-60"
        :disabled="isGoing"
        data-testid="teams-sign-in"
        @click="signIn"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true">
          <rect x="1" y="1" width="10.5" height="10.5" fill="#F25022" />
          <rect x="12.5" y="1" width="10.5" height="10.5" fill="#7FBA00" />
          <rect x="1" y="12.5" width="10.5" height="10.5" fill="#00A4EF" />
          <rect x="12.5" y="12.5" width="10.5" height="10.5" fill="#FFB900" />
        </svg>
        {{ t('OUTSIDER_TEAMS_GRAPH.SIGN_IN') }}
      </button>
      <p class="flex items-center gap-1 mt-2.5 mb-0 text-xs text-n-slate-10">
        <Icon icon="i-lucide-lock" class="size-3" />
        {{ t('OUTSIDER_TEAMS_GRAPH.NO_PASSWORD') }}
      </p>
    </template>
    <p v-else class="max-w-sm mb-0 text-sm text-n-slate-11">
      {{
        info.admin
          ? t('OUTSIDER_TEAMS_GRAPH.NEEDS_APP_ADMIN')
          : t('OUTSIDER_TEAMS_GRAPH.NEEDS_APP')
      }}
    </p>
  </section>

  <!-- conectado -->
  <div v-else class="flex flex-col gap-4" data-testid="teams-my-card">
    <section
      class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
    >
      <div class="flex flex-wrap items-center gap-3.5">
        <Avatar :name="me.display_name || '?'" :size="46" rounded-full />
        <div class="flex-1 min-w-[200px]">
          <h3
            class="flex flex-wrap items-center gap-2 mb-0 text-[15px] font-semibold text-n-slate-12"
          >
            {{ t('OUTSIDER_TEAMS_GRAPH.MY_TITLE') }}
            <span
              v-if="me.status === 'active'"
              class="flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
            >
              <Icon icon="i-lucide-check" class="size-3" />
              {{ t('OUTSIDER_TEAMS_GRAPH.CONNECTED') }}
            </span>
            <span
              v-else
              class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-amber-3 text-n-amber-11"
            >
              {{ t('OUTSIDER_TEAMS_GRAPH.NEEDS_RECONNECT') }}
            </span>
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ me.email || me.display_name }}
          </p>
        </div>
        <Button
          sm
          slate
          faded
          icon="i-lucide-refresh-cw"
          :label="t('OUTSIDER_TEAMS_GRAPH.SIGN_IN_AGAIN')"
          :is-loading="isGoing"
          @click="signIn"
        />
        <Button
          sm
          ruby
          faded
          icon="i-lucide-unplug"
          :label="t('OUTSIDER_TEAMS_GRAPH.DISCONNECT')"
          @click="disconnect"
        />
      </div>
      <p
        v-if="me.status === 'reconnect'"
        class="flex items-start gap-2 p-2.5 mt-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
        {{ t('OUTSIDER_TEAMS_GRAPH.RECONNECT_HELP') }}
      </p>
      <p
        v-else-if="problems.length"
        class="flex items-start gap-2 p-2.5 mt-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
        {{
          t('OUTSIDER_TEAMS_GRAPH.NOTICES_PROBLEM', {
            reason:
              problems[0].error || t('OUTSIDER_TEAMS_GRAPH.NOTICES_NO_REASON'),
          })
        }}
      </p>
      <p
        v-if="working"
        class="flex items-center gap-2 p-2.5 mt-3 mb-0 text-sm rounded-xl tms-soft"
        data-testid="teams-working"
      >
        <Spinner :size="14" class="shrink-0" />
        {{ t('OUTSIDER_TEAMS_GRAPH.WORKING') }}
      </p>
    </section>

    <section
      v-if="me.status === 'active'"
      class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
    >
      <h3 class="mb-0.5 text-[15px] font-semibold text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_GRAPH.WHAT_TITLE') }}
      </h3>
      <p class="mb-3 text-sm text-n-slate-11">
        {{ t('OUTSIDER_TEAMS_GRAPH.WHAT_HELP') }}
      </p>
      <label
        class="flex items-center gap-3.5 p-3 mb-4 border cursor-pointer rounded-xl border-n-weak bg-n-surface-1"
      >
        <span
          class="flex items-center justify-center size-9 rounded-xl tms-soft"
        >
          <Icon icon="i-lucide-message-circle" class="size-[18px]" />
        </span>
        <span class="flex-1">
          <span class="block text-sm font-semibold text-n-slate-12">
            {{ t('OUTSIDER_TEAMS_GRAPH.MY_CHATS') }}
          </span>
          <span class="block text-xs text-n-slate-11">
            {{ t('OUTSIDER_TEAMS_GRAPH.MY_CHATS_HELP') }}
          </span>
        </span>
        <input
          v-model="syncChats"
          type="checkbox"
          class="!m-0 size-5 accent-[#5b5fc7]"
        />
      </label>

      <label
        class="flex items-center gap-3.5 p-3 mb-3 border cursor-pointer rounded-xl border-n-weak bg-n-surface-1"
        data-testid="teams-all-channels"
      >
        <span
          class="flex items-center justify-center size-9 rounded-xl tms-soft"
        >
          <Icon icon="i-lucide-layers" class="size-[18px]" />
        </span>
        <span class="flex-1">
          <span class="block text-sm font-semibold text-n-slate-12">
            {{ t('OUTSIDER_TEAMS_GRAPH.ALL_CHANNELS') }}
          </span>
          <span class="block text-xs text-n-slate-11">
            {{ t('OUTSIDER_TEAMS_GRAPH.ALL_CHANNELS_HELP') }}
          </span>
        </span>
        <input
          :checked="allChannels"
          type="checkbox"
          class="!m-0 size-5 accent-[#5b5fc7]"
          @change="setAllChannels($event.target.checked)"
        />
      </label>

      <div
        class="flex items-center gap-2 mb-2 text-sm font-semibold text-n-slate-12"
      >
        <Icon icon="i-lucide-hash" class="size-4" />
        {{ t('OUTSIDER_TEAMS_GRAPH.MY_CHANNELS') }}
        <span class="px-2 py-0.5 text-xs rounded-full tms-soft">
          {{ t('OUTSIDER_TEAMS_GRAPH.CHOSEN', { count: chosen.size }) }}
        </span>
        <button
          type="button"
          class="ml-auto text-xs font-normal text-n-slate-11 hover:text-n-slate-12"
          @click="loadDirectory(true)"
        >
          <Icon icon="i-lucide-refresh-cw" class="size-3" />
          {{ t('OUTSIDER_TEAMS_GRAPH.RELOAD_TEAMS') }}
        </button>
      </div>
      <div v-if="isLoadingTeams" class="flex justify-center py-6">
        <Spinner :size="18" />
      </div>
      <p
        v-else-if="!directory.length"
        class="py-3 mb-0 text-sm text-n-slate-11"
      >
        {{ t('OUTSIDER_TEAMS_GRAPH.NO_TEAMS') }}
      </p>
      <div v-else class="grid gap-2.5 sm:grid-cols-2 xl:grid-cols-3">
        <div
          v-for="team in directory"
          :key="team.team_id"
          class="px-3.5 py-2.5 border rounded-xl border-n-weak bg-n-surface-1"
        >
          <div
            class="flex items-center gap-2 mb-1 text-sm font-semibold text-n-slate-12"
          >
            <Avatar :name="team.team_name || '?'" :size="22" />
            <span class="truncate">{{ team.team_name }}</span>
          </div>
          <label
            v-for="channel in team.channels"
            :key="channel.channel_id"
            class="flex items-center gap-2 py-1 text-sm cursor-pointer text-n-slate-12"
          >
            <input
              type="checkbox"
              class="!m-0 size-4 accent-[#5b5fc7]"
              :checked="
                chosen.has(channelKey(team.team_id, channel.channel_id))
              "
              @change="toggle(team.team_id, channel.channel_id)"
            />
            <Icon icon="i-lucide-hash" class="size-3.5 text-n-slate-10" />
            <span class="truncate">{{ channel.channel_name }}</span>
            <Icon
              v-if="channel.membership === 'private'"
              v-tooltip.top="t('OUTSIDER_TEAMS_GRAPH.PRIVATE_CHANNEL')"
              icon="i-lucide-lock"
              class="size-3 text-n-slate-10"
            />
          </label>
        </div>
      </div>
      <div class="flex justify-end mt-4">
        <button
          type="button"
          class="px-4 py-2 text-sm font-semibold rounded-xl tms-accent-bg disabled:opacity-60"
          :disabled="isSaving"
          data-testid="teams-save-choices"
          @click="save"
        >
          {{ t('OUTSIDER_TEAMS_GRAPH.SAVE_CHOICES') }}
        </button>
      </div>
    </section>
  </div>
</template>
