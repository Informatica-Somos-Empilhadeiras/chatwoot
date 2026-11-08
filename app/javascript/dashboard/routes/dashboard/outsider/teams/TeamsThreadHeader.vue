<script setup>
// OUTSIDER: cabeçalho do chat ou do canal aberto na área Teams. Sem Resolver, Atribuir ou CRM: é
// conversa interna, não atendimento. "Abrir no Teams" abre a mesma conversa no Teams. No canal, a pessoa
// escolhe como ver: Conversa (em sequência, como no WhatsApp) ou Publicações (cartões, como no Teams).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeamsLogo from './TeamsLogo.vue';

const props = defineProps({
  thread: { type: Object, required: true },
  // só no canal: 'conversa' | 'publicacoes'
  viewMode: { type: String, default: null },
});
const emit = defineEmits(['back', 'changeView']);

const VIEWS = [
  { id: 'conversa', icon: 'i-lucide-messages-square', label: 'VIEW_CONVERSA' },
  { id: 'publicacoes', icon: 'i-lucide-layout-list', label: 'VIEW_POSTS' },
];
const { t } = useI18n();

const subtitle = computed(() => {
  const { thread } = props;
  if (thread.kind === 'channel')
    return t('OUTSIDER_TEAMS_AREA.CHANNEL_OF', { team: thread.team_name || '' });
  if (thread.chat_type === 'oneOnOne') return t('OUTSIDER_TEAMS_AREA.CHAT_1_1');
  if (thread.chat_type === 'meeting') return t('OUTSIDER_TEAMS_AREA.CHAT_MEETING');
  return t('OUTSIDER_TEAMS_AREA.CHAT_GROUP', { count: thread.members_count });
});
</script>

<template>
  <header
    class="flex items-center gap-3 px-4 py-3 border-b md:px-5 border-n-weak bg-n-surface-1"
  >
    <button
      type="button"
      class="md:hidden text-n-slate-11"
      :aria-label="t('OUTSIDER_TEAMS_AREA.BACK')"
      @click="emit('back')"
    >
      <Icon icon="i-lucide-chevron-left" class="size-6" />
    </button>
    <span
      v-if="thread.kind === 'channel'"
      class="flex items-center justify-center size-10 rounded-xl tms-soft shrink-0"
    >
      <Icon icon="i-lucide-hash" class="size-5" />
    </span>
    <span v-else class="relative shrink-0">
      <Avatar
        :name="thread.title || '?'"
        :size="40"
        :rounded-full="thread.chat_type === 'oneOnOne'"
      />
      <span class="absolute -right-1 -bottom-1 rounded-full bg-n-surface-1 p-px">
        <TeamsLogo :size="15" />
      </span>
    </span>
    <span class="flex-1 min-w-0">
      <span class="block font-semibold truncate text-n-slate-12">
        {{ thread.title || t('OUTSIDER_TEAMS_AREA.UNTITLED') }}
      </span>
      <span class="block text-xs truncate text-n-slate-11">{{ subtitle }}</span>
    </span>
    <div
      v-if="thread.kind === 'channel' && viewMode"
      class="flex p-0.5 rounded-xl bg-n-alpha-1 shrink-0"
      role="tablist"
      data-teams-view
    >
      <button
        v-for="view in VIEWS"
        :key="view.id"
        type="button"
        role="tab"
        class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-semibold rounded-[10px]"
        :class="
          viewMode === view.id
            ? 'bg-n-surface-1 shadow-sm tms-text'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        :aria-selected="viewMode === view.id"
        :title="t(`OUTSIDER_TEAMS_AREA.${view.label}_HINT`)"
        @click="viewMode !== view.id && emit('changeView', view.id)"
      >
        <Icon :icon="view.icon" class="size-4" />
        <span class="hidden lg:inline">
          {{ t(`OUTSIDER_TEAMS_AREA.${view.label}`) }}
        </span>
      </button>
    </div>
    <a
      :href="thread.web_url"
      target="_blank"
      rel="noopener noreferrer"
      class="flex items-center gap-2 px-3 py-2 text-sm font-semibold border-[1.5px] rounded-xl tms-border tms-text hover:bg-n-alpha-1 shrink-0"
    >
      <TeamsLogo :size="16" />
      <span class="hidden sm:inline">{{ t('OUTSIDER_TEAMS_AREA.OPEN_IN_TEAMS') }}</span>
    </a>
  </header>
</template>
