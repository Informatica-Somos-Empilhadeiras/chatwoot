<script setup>
// OUTSIDER: barra "Você foi citado N vezes" no topo de um chat ou canal da área Teams, com ‹ › para ir de uma
// citação à outra (a mensagem fica destacada). Só aparece quando a pessoa foi citada nos últimos 60 dias.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';

const props = defineProps({
  thread: { type: Object, required: true },
  // ids das mensagens que a tela já tem carregadas (para pular sem buscar)
  loadedIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['jump']);

const { t } = useI18n();
const mentions = ref([]);
const index = ref(-1);
const hidden = ref(false);

const total = computed(() => mentions.value.length);
const current = computed(() => mentions.value[index.value] || null);

const load = async () => {
  try {
    const { data } = await TeamsGraphAPI.mentions(props.thread.id);
    mentions.value = data.payload || [];
    // começa na última citação (a mais nova)
    index.value = mentions.value.length - 1;
  } catch {
    mentions.value = [];
  }
};

const go = step => {
  if (!total.value) return;
  index.value = (index.value + step + total.value) % total.value;
  emit('jump', mentions.value[index.value]);
};

const goCurrent = () => {
  if (current.value) emit('jump', current.value);
};

onMounted(load);
// citado de novo enquanto a conversa está aberta: a barra atualiza
watch(() => props.thread.mention_count, load);

defineExpose({ reload: load });
</script>

<template>
  <div
    v-if="total && !hidden"
    class="flex items-center gap-2 px-4 py-1.5 text-xs border-b md:px-8 tms-soft border-n-weak"
    data-teams-mention-bar
  >
    <Icon icon="i-lucide-at-sign" class="size-3.5 shrink-0" />
    <button
      type="button"
      class="font-semibold truncate hover:underline"
      @click="goCurrent"
    >
      {{ t('OUTSIDER_TEAMS_AREA.MENTION_BAR', { count: total }) }}
    </button>
    <span v-if="current" class="truncate text-n-slate-11">
      · {{ current.sender_name }}
    </span>
    <span class="flex items-center gap-0.5 ml-auto shrink-0">
      <button
        type="button"
        class="grid rounded-md size-6 place-items-center hover:bg-n-alpha-2"
        :title="t('OUTSIDER_TEAMS_AREA.MENTION_PREV')"
        data-teams-mention-prev
        @click="go(-1)"
      >
        <Icon icon="i-lucide-chevron-up" class="size-4" />
      </button>
      <span class="min-w-[2.5rem] text-center tabular-nums">
        {{ index + 1 }}/{{ total }}
      </span>
      <button
        type="button"
        class="grid rounded-md size-6 place-items-center hover:bg-n-alpha-2"
        :title="t('OUTSIDER_TEAMS_AREA.MENTION_NEXT')"
        data-teams-mention-next
        @click="go(1)"
      >
        <Icon icon="i-lucide-chevron-down" class="size-4" />
      </button>
      <button
        type="button"
        class="grid ml-1 rounded-md size-6 place-items-center hover:bg-n-alpha-2"
        :title="t('OUTSIDER_TEAMS_AREA.MENTION_HIDE')"
        @click="hidden = true"
      >
        <Icon icon="i-lucide-x" class="size-3.5" />
      </button>
    </span>
  </div>
</template>
