<script setup>
// OUTSIDER: a lista de blocos do estúdio: os que servem para qualquer relatório e os do tipo (checklist com as fotos na
// OS, totais no orçamento). Arraste para a folha ou clique para pôr depois do bloco selecionado (sem seleção, no fim).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import {
  BLOCK_ICONS,
  GENERIC_TYPES,
  MAX_BLOCKS,
  newBlock,
} from './printsHelpers';

const props = defineProps({
  catalog: { type: Object, required: true },
  blocks: { type: Array, required: true },
});

const emit = defineEmits(['add']);

const { t } = useI18n();

const full = computed(() => props.blocks.length >= MAX_BLOCKS);
const types = computed(() =>
  (props.catalog.blocks || []).map(item => item.type)
);
const generic = computed(() =>
  GENERIC_TYPES.filter(type => types.value.includes(type)).map(type => ({
    type,
  }))
);
const context = computed(() =>
  types.value
    .filter(type => !GENERIC_TYPES.includes(type))
    .map(type => ({ type }))
);

const toBlock = tile => newBlock(props.catalog, tile.type, props.blocks);
const add = tile => {
  if (!full.value) emit('add', toBlock(tile));
};
const onMove = () => !full.value;

const groups = computed(() => [
  { key: 'CONTEXT', tiles: context.value, accent: true },
  { key: 'GENERIC', tiles: generic.value, accent: false },
]);
</script>

<template>
  <div class="flex flex-col gap-5">
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_ERP.PRINTS.STUDIO.PALETTE_HELP') }}
    </p>
    <section
      v-for="group in groups"
      :key="group.key"
      class="flex flex-col gap-2"
    >
      <h4
        class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{
          t(
            group.key === 'CONTEXT'
              ? `OUTSIDER_ERP.PRINTS.STUDIO.PALETTE_CONTEXT_${catalog.kind.toUpperCase()}`
              : 'OUTSIDER_ERP.PRINTS.STUDIO.PALETTE_GENERIC'
          )
        }}
      </h4>
      <Draggable
        :list="group.tiles"
        :item-key="tile => tile.type"
        :group="{ name: 'print-blocks', pull: 'clone', put: false }"
        :clone="toBlock"
        :sort="false"
        :move="onMove"
        class="grid grid-cols-2 gap-2"
      >
        <template #item="{ element }">
          <button
            type="button"
            class="flex flex-col items-center justify-center gap-1.5 p-2 text-xs font-medium text-center rounded-xl min-h-[4.75rem] outline outline-1 -outline-offset-1 select-none"
            :class="[
              full
                ? 'opacity-50 cursor-not-allowed outline-n-weak text-n-slate-10'
                : 'cursor-grab bg-n-solid-1 text-n-slate-12 hover:outline-n-brand hover:text-n-blue-11',
              group.accent && !full ? 'outline-n-teal-7' : 'outline-n-weak',
            ]"
            :data-palette-tile="element.type"
            @click="add(element)"
          >
            <span
              :class="BLOCK_ICONS[element.type]"
              class="size-5"
              :style="{ color: group.accent ? '#00663B' : undefined }"
            />
            {{ t(`OUTSIDER_ERP.PRINTS.BLOCKS.${element.type.toUpperCase()}`) }}
          </button>
        </template>
      </Draggable>
    </section>
    <span v-if="full" class="text-xs text-n-amber-11">
      {{ t('OUTSIDER_ERP.PRINTS.STUDIO.FULL', { max: MAX_BLOCKS }) }}
    </span>
  </div>
</template>
