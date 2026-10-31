<script setup>
// OUTSIDER: lista de blocos do editor do bot, no estilo das ferramentas de automação: busca no topo, uma
// aba por tipo (Conversa, Lógica, Integrações, Arquivos) e cada bloco com ícone, nome e o que faz.
// Clique adiciona (ligado ao bloco escolhido); arrastar solta no quadro. A aba fica lembrada no navegador.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { NODE_TYPES, PALETTE_CATEGORIES, PALETTE_WORDS } from './nodeTypes';

const emit = defineEmits(['add', 'dragstart']);
const { t } = useI18n();

const TAB_KEY = 'outsider-bot-palette-tab';
const readTab = () => {
  try {
    const saved = window.localStorage.getItem(TAB_KEY);
    return PALETTE_CATEGORIES.some(category => category.id === saved)
      ? saved
      : PALETTE_CATEGORIES[0].id;
  } catch {
    return PALETTE_CATEGORIES[0].id;
  }
};
const tab = ref(readTab());
const chooseTab = id => {
  tab.value = id;
  try {
    window.localStorage.setItem(TAB_KEY, id);
  } catch {
    // sem armazenamento no navegador: só não lembra a aba
  }
};

const query = ref('');
const searchInput = ref(null);
const normalize = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

const typeTitle = type => t(`OUTSIDER_TOOLS.BOT.TYPES.${type}`);
const typeHint = type => t(`OUTSIDER_TOOLS.BOT.TYPE_HINTS.${type}`);
const categoryLabel = id => t(`OUTSIDER_TOOLS.BOT.PALETTE.TABS.${id}`);
const sectionLabel = id =>
  id ? t(`OUTSIDER_TOOLS.BOT.PALETTE.SECTIONS.${id}`) : '';

const category = computed(
  () =>
    PALETTE_CATEGORIES.find(item => item.id === tab.value) ||
    PALETTE_CATEGORIES[0]
);

// buscando: uma seção por aba, só com os blocos que têm todas as palavras digitadas
const sections = computed(() => {
  const words = normalize(query.value).split(/\s+/).filter(Boolean);
  if (!words.length) {
    return category.value.sections.map(section => ({
      key: section.id || 'all',
      label: sectionLabel(section.id),
      types: section.types,
    }));
  }
  return PALETTE_CATEGORIES.map(item => ({
    key: item.id,
    label: categoryLabel(item.id),
    types: item.sections
      .flatMap(section => section.types)
      .filter(type => {
        const text = normalize(
          `${typeTitle(type)} ${typeHint(type)} ${PALETTE_WORDS[type] || ''}`
        );
        return words.every(word => text.includes(word));
      }),
  })).filter(section => section.types.length);
});

const addFirst = () => {
  const first = sections.value[0]?.types[0];
  if (first) emit('add', first);
};

defineExpose({ focusSearch: () => searchInput.value?.focus() });
</script>

<template>
  <aside
    class="flex flex-col min-h-0 border-r w-64 shrink-0 border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-2 p-3 pb-2.5 border-b border-n-weak">
      <div class="relative">
        <Icon
          icon="i-lucide-search"
          class="absolute -translate-y-1/2 pointer-events-none size-4 top-1/2 ltr:left-2.5 rtl:right-2.5 text-n-slate-10"
        />
        <input
          ref="searchInput"
          v-model="query"
          type="text"
          maxlength="40"
          class="!mb-0 !h-9 !text-sm ltr:!pl-8 rtl:!pr-8"
          :placeholder="t('OUTSIDER_TOOLS.BOT.PALETTE.SEARCH')"
          @keydown.esc="query = ''"
          @keydown.enter.prevent="addFirst"
        />
      </div>
      <div v-if="!query.trim()" class="grid grid-cols-2 gap-1" role="tablist">
        <button
          v-for="item in PALETTE_CATEGORIES"
          :key="item.id"
          type="button"
          role="tab"
          :aria-selected="tab === item.id"
          class="flex items-center gap-1.5 h-8 px-2 text-xs rounded-lg transition-colors"
          :class="
            tab === item.id
              ? 'bg-n-brand/10 text-n-brand font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
          "
          @click="chooseTab(item.id)"
        >
          <Icon :icon="item.icon" class="size-4 shrink-0" />
          <span class="truncate">{{ categoryLabel(item.id) }}</span>
        </button>
      </div>
    </div>

    <div class="flex-1 min-h-0 p-2 overflow-y-auto">
      <div
        v-for="section in sections"
        :key="section.key"
        class="flex flex-col gap-0.5 mb-2 last:mb-0"
      >
        <span
          v-if="section.label"
          class="px-2 pt-1.5 pb-1 text-[10px] font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ section.label }}
        </span>
        <button
          v-for="type in section.types"
          :key="type"
          type="button"
          draggable="true"
          :data-palette-type="type"
          class="flex items-center w-full gap-3 px-2 py-2 text-left rounded-lg group cursor-grab active:cursor-grabbing hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1"
          @dragstart="emit('dragstart', type, $event)"
          @click="emit('add', type)"
        >
          <span
            class="flex items-center justify-center rounded-lg size-9 shrink-0"
            :class="NODE_TYPES[type].soft"
          >
            <Icon :icon="NODE_TYPES[type].icon" class="size-[18px]" />
          </span>
          <span class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ typeTitle(type) }}
            </span>
            <span class="text-xs leading-snug line-clamp-2 text-n-slate-11">
              {{ typeHint(type) }}
            </span>
          </span>
          <Icon
            icon="i-lucide-grip-vertical"
            class="size-4 shrink-0 text-n-slate-8 opacity-0 group-hover:opacity-100"
          />
        </button>
      </div>
      <p
        v-if="query.trim() && !sections.length"
        class="px-2 py-6 mb-0 text-sm text-center text-n-slate-11"
      >
        {{
          t('OUTSIDER_TOOLS.BOT.PALETTE.NO_RESULTS', { query: query.trim() })
        }}
      </p>
    </div>

    <p
      class="px-3 py-2.5 mb-0 text-[11px] leading-snug border-t border-n-weak text-n-slate-10"
    >
      {{ t('OUTSIDER_TOOLS.BOT.PALETTE.HINT') }}
    </p>
  </aside>
</template>
