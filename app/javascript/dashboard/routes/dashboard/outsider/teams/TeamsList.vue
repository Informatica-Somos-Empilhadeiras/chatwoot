<script setup>
// OUTSIDER: lista da área Teams. Abas Chats e Canais (com as não lidas); os chats em ordem da última
// mensagem e os canais agrupados por equipe. A busca filtra pelo nome e pela última mensagem.
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeamsLogo from './TeamsLogo.vue';
import { TEAMS_ROUTE } from './teamsStore';
import { listTime } from './helpers';

const props = defineProps({
  threads: { type: Array, default: () => [] },
  kind: { type: String, default: 'chat' },
  routeKind: { type: String, default: 'chats' },
  selectedId: { type: Number, default: null },
  isLoading: { type: Boolean, default: false },
  status: { type: String, default: null },
  unreadChats: { type: Number, default: 0 },
  unreadChannels: { type: Number, default: 0 },
});

const emit = defineEmits(['open', 'settings']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const search = ref('');

const filtered = computed(() => {
  const term = search.value.trim().toLowerCase();
  if (!term) return props.threads;
  return props.threads.filter(thread =>
    [thread.title, thread.team_name, thread.last_message_preview]
      .filter(Boolean)
      .some(text => text.toLowerCase().includes(term))
  );
});

// canais: [{ team, items }] em ordem alfabética da equipe
const teams = computed(() => {
  const groups = {};
  filtered.value.forEach(thread => {
    const team = thread.team_name || t('OUTSIDER_TEAMS_AREA.TEAM_FALLBACK');
    (groups[team] ||= []).push(thread);
  });
  return Object.keys(groups)
    .sort((a, b) => a.localeCompare(b))
    .map(team => ({
      team,
      items: groups[team].sort((a, b) =>
        (a.title || '').localeCompare(b.title || '')
      ),
    }));
});

const subtitle = thread => {
  if (thread.chat_type === 'oneOnOne') return t('OUTSIDER_TEAMS_AREA.CHAT_1_1');
  if (thread.chat_type === 'meeting') return t('OUTSIDER_TEAMS_AREA.CHAT_MEETING');
  return t('OUTSIDER_TEAMS_AREA.CHAT_GROUP', { count: thread.members_count });
};

const goTab = routeKind =>
  router.push({
    name: TEAMS_ROUTE,
    params: { accountId: route.params.accountId, kind: routeKind },
  });
</script>

<template>
  <aside class="flex-col min-h-0 px-2.5">
    <header class="flex items-center gap-2 px-1.5 pt-5 pb-3">
      <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_AREA.TITLE') }}
      </h2>
      <span
        v-if="status === 'active'"
        class="flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-md tms-soft"
      >
        <span class="rounded-full size-1.5 bg-n-teal-9" />
        {{ t('OUTSIDER_TEAMS_AREA.CONNECTED') }}
      </span>
      <button
        v-else-if="status"
        type="button"
        class="px-2 py-0.5 text-xs rounded-md bg-n-amber-3 text-n-amber-11"
        @click="emit('settings')"
      >
        {{
          status === 'reconnect'
            ? t('OUTSIDER_TEAMS_AREA.NEEDS_RECONNECT')
            : t('OUTSIDER_TEAMS_AREA.DISCONNECTED')
        }}
      </button>
      <Spinner v-if="isLoading" :size="14" class="text-n-slate-10" />
    </header>

    <label
      class="flex items-center gap-2 px-3 py-2.5 mx-1 mb-2.5 rounded-2xl bg-n-alpha-2 text-n-slate-10"
    >
      <Icon icon="i-lucide-search" class="size-4 shrink-0" />
      <input
        v-model="search"
        type="text"
        class="!m-0 !p-0 !border-0 !bg-transparent !h-auto !shadow-none text-sm text-n-slate-12 w-full outline-none"
        :placeholder="t('OUTSIDER_TEAMS_AREA.SEARCH')"
      />
    </label>

    <nav class="flex gap-1 p-1 mx-1 mb-2 rounded-2xl bg-n-alpha-2">
      <button
        v-for="tab in [
          { key: 'chats', icon: 'i-lucide-message-circle', count: unreadChats },
          { key: 'channels', icon: 'i-lucide-hash', count: unreadChannels },
        ]"
        :key="tab.key"
        type="button"
        class="flex items-center justify-center flex-1 gap-1.5 py-1.5 text-sm rounded-xl"
        :class="
          routeKind === tab.key
            ? 'tms-accent-bg font-semibold'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="goTab(tab.key)"
      >
        <Icon :icon="tab.icon" class="size-4" />
        {{
          tab.key === 'chats'
            ? t('OUTSIDER_TEAMS_AREA.TABS.CHATS')
            : t('OUTSIDER_TEAMS_AREA.TABS.CHANNELS')
        }}
        <span
          v-if="tab.count"
          class="px-1.5 text-[11px] font-bold leading-[17px] rounded-full"
          :class="routeKind === tab.key ? 'bg-white/25' : 'tms-soft'"
        >
          {{ tab.count }}
        </span>
      </button>
    </nav>

    <div class="flex-1 min-h-0 pb-4 overflow-y-auto">
      <!-- chats -->
      <template v-if="kind === 'chat'">
        <button
          v-for="thread in filtered"
          :key="thread.id"
          type="button"
          class="flex items-start w-full gap-3 p-2.5 text-left rounded-2xl"
          :class="
            thread.id === selectedId ? 'tms-soft !text-inherit' : 'hover:bg-n-alpha-1'
          "
          data-testid="teams-thread"
          @click="emit('open', thread)"
        >
          <span class="relative shrink-0">
            <Avatar
              :name="thread.title || '?'"
              :size="42"
              :rounded-full="thread.chat_type === 'oneOnOne'"
            />
            <span
              class="absolute -right-1 -bottom-1 rounded-full bg-n-surface-1 p-px"
            >
              <TeamsLogo :size="15" />
            </span>
          </span>
          <span class="flex-1 min-w-0">
            <span class="flex items-baseline gap-2">
              <span
                class="flex-1 text-sm font-semibold truncate text-n-slate-12"
              >
                {{ thread.title || t('OUTSIDER_TEAMS_AREA.UNTITLED') }}
              </span>
              <span
                class="text-xs shrink-0"
                :class="thread.unread_count ? 'tms-text font-semibold' : 'text-n-slate-10'"
              >
                {{ listTime(thread.last_message_at, t) }}
              </span>
            </span>
            <span class="flex items-center gap-2 mt-0.5">
              <span
                class="flex-1 text-sm truncate"
                :class="thread.unread_count ? 'text-n-slate-12 font-medium' : 'text-n-slate-11'"
              >
                {{ thread.last_message_preview }}
              </span>
              <span
                v-if="thread.mention_count"
                class="tms-count"
                :title="t('OUTSIDER_TEAMS_AREA.MENTIONED_YOU')"
              >
                @
              </span>
              <span v-if="thread.unread_count" class="tms-count">
                {{ thread.unread_count }}
              </span>
            </span>
            <span class="block mt-0.5 text-xs text-n-slate-10">
              {{ subtitle(thread) }}
            </span>
          </span>
        </button>
      </template>

      <!-- canais por equipe -->
      <template v-else>
        <div v-for="group in teams" :key="group.team" class="mb-1">
          <div
            class="flex items-center gap-2 px-2.5 pt-3 pb-1 text-[11px] font-bold tracking-wide uppercase text-n-slate-11"
          >
            <Avatar :name="group.team" :size="20" />
            {{ group.team }}
          </div>
          <button
            v-for="thread in group.items"
            :key="thread.id"
            type="button"
            class="flex items-center w-full gap-2.5 px-2.5 py-2 text-left rounded-xl"
            :class="
              thread.id === selectedId ? 'tms-soft !text-inherit' : 'hover:bg-n-alpha-1'
            "
            data-testid="teams-thread"
            @click="emit('open', thread)"
          >
            <span
              class="flex items-center justify-center rounded-lg size-8 shrink-0"
              :class="thread.id === selectedId ? 'tms-accent-bg' : 'bg-n-alpha-2 text-n-slate-11'"
            >
              <Icon icon="i-lucide-hash" class="size-4" />
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-sm font-semibold truncate text-n-slate-12">
                {{ thread.title }}
              </span>
              <span class="block text-xs truncate text-n-slate-11">
                {{ thread.last_message_preview }}
              </span>
            </span>
            <span
              v-if="thread.mention_count"
              class="tms-count"
              :title="t('OUTSIDER_TEAMS_AREA.MENTIONED_YOU')"
            >
              @
            </span>
            <span v-if="thread.unread_count" class="tms-count">
              {{ thread.unread_count }}
            </span>
          </button>
        </div>
        <button
          type="button"
          class="flex items-center gap-2 px-2.5 mt-3 text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="emit('settings')"
        >
          <Icon icon="i-lucide-settings-2" class="size-4" />
          {{ t('OUTSIDER_TEAMS_AREA.PICK_CHANNELS') }}
        </button>
      </template>

      <p
        v-if="!isLoading && !filtered.length"
        class="px-4 py-8 mb-0 text-sm text-center text-n-slate-11"
      >
        {{
          search
            ? t('OUTSIDER_TEAMS_AREA.NOTHING_FOUND')
            : kind === 'chat'
              ? t('OUTSIDER_TEAMS_AREA.EMPTY_CHATS')
              : t('OUTSIDER_TEAMS_AREA.EMPTY_CHANNELS')
        }}
      </p>
    </div>
  </aside>
</template>
