<script setup>
// OUTSIDER: abas Minhas / Esperando / Grupos / Todos como as pastas do Telegram: pílulas dentro de
// uma barra arredondada, a aba ativa preenchida e o número de conversas em cada uma. Entra no
// lugar do ChatTypeTabs.vue (troca de import no ChatList.vue), com as mesmas propriedades,
// o mesmo evento e o mesmo atalho Alt+N.
import { computed, ref, watch, nextTick, onMounted } from 'vue';
import { useResizeObserver } from '@vueuse/core';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: { type: Array, default: () => [] },
  activeTab: { type: String, default: wootConstants.ASSIGNEE_TYPE.ME },
  isCompact: { type: Boolean, default: false },
});

const emit = defineEmits(['chatTabChange']);

const scroller = ref(null);
const activeIndex = computed(() =>
  props.items.findIndex(item => item.key === props.activeTab)
);

const select = index => {
  const item = props.items[index];
  if (item && item.key !== props.activeTab) emit('chatTabChange', item.key);
};

const formatCount = count => (count > 999 ? '999+' : count);

// lista estreita: só a aba ativa mostra o número, para todas caberem sem rolar
const tight = ref(false);
let fullWidth = 0;
const measure = () => {
  const el = scroller.value;
  if (!el) return;
  if (!tight.value) fullWidth = el.scrollWidth;
  tight.value = fullWidth > el.clientWidth + 1;
};
const remeasure = async () => {
  tight.value = false;
  await nextTick();
  measure();
};
watch(
  () => props.items.map(item => `${item.key}:${item.count}`).join(),
  remeasure
);
onMounted(remeasure);
useResizeObserver(scroller, measure);
const showCount = (item, index) =>
  !!item.count && (!tight.value || index === activeIndex.value);

// a aba escolhida fica sempre visível quando a lista é estreita
watch(activeIndex, async index => {
  await nextTick();
  scroller.value
    ?.querySelectorAll('[data-folder-tab]')
    [index]?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
});

useKeyboardEvents({
  'Alt+KeyN': {
    action: () => {
      if (props.activeTab === wootConstants.ASSIGNEE_TYPE.ALL) select(0);
      else select((activeIndex.value + 1) % props.items.length);
    },
  },
});
</script>

<template>
  <div class="px-3 pt-1 pb-2">
    <div
      ref="scroller"
      class="flex items-center gap-0.5 p-1 overflow-x-auto rounded-2xl bg-n-alpha-1 dark:bg-n-alpha-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      role="tablist"
    >
      <button
        v-for="(item, index) in items"
        :key="item.key"
        type="button"
        role="tab"
        data-folder-tab
        :aria-selected="index === activeIndex"
        class="flex items-center justify-center flex-1 gap-1 px-2.5 h-8 text-[13px] whitespace-nowrap rounded-xl transition-colors duration-150 min-w-fit"
        :class="
          index === activeIndex
            ? 'bg-n-brand text-white font-semibold shadow-sm'
            : 'text-n-slate-11 font-medium hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        @click="select(index)"
      >
        <span>{{ item.name }}</span>
        <span
          v-if="showCount(item, index)"
          class="inline-grid place-items-center h-4 min-w-4 px-1 rounded-full text-[10px] font-bold leading-none tabular-nums"
          :class="
            index === activeIndex
              ? 'bg-white/25 text-white'
              : 'bg-n-slate-9/25 text-n-slate-11'
          "
        >
          {{ formatCount(item.count) }}
        </span>
      </button>
    </div>
  </div>
</template>
