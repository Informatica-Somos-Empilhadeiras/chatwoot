<script setup>
// OUTSIDER: lista de blocos na esquerda do editor (Entrega 17), como a da Brevo: arraste um bloco para a
// folha ou clique para pôr depois do bloco selecionado (sem seleção, no fim). Os blocos livres (texto,
// imagem, linha, espaço) entram quantas vezes quiser; os blocos da proposta aparecem uma vez cada, e os
// que estão escondidos voltam daqui.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { BLOCK_INFO, FREE_TYPES, MAX_BLOCKS, freeBlock } from './templateDesign';

const props = defineProps({
  blocks: { type: Array, required: true },
});

const emit = defineEmits(['add']);

const { t } = useI18n();

const full = computed(() => props.blocks.length >= MAX_BLOCKS);

const freeTiles = computed(() =>
  FREE_TYPES.map(type => ({ id: `free-${type}`, type, free: true }))
);

const proposalTiles = computed(() =>
  props.blocks
    .filter(block => !FREE_TYPES.includes(block.type))
    .map(block => ({
      id: block.key,
      type: block.type,
      free: false,
      block,
      onSheet: block.visible,
    }))
);

const name = type =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.TYPES.${type.toUpperCase()}`);

// o que cai na folha: bloco livre novo ou o bloco da proposta que estava escondido
const toBlock = tile =>
  tile.free ? freeBlock(tile.type) : { ...tile.block, visible: true };

const canDrop = tile => (tile.free ? !full.value : !tile.onSheet);

const add = tile => {
  if (canDrop(tile)) emit('add', toBlock(tile));
};

const onMove = event => canDrop(event.draggedContext.element);

const TILE =
  'flex flex-col items-center justify-center gap-1.5 p-2 text-xs font-medium text-center rounded-xl min-h-[5.5rem] outline outline-1 -outline-offset-1 select-none';
</script>

<template>
  <div class="flex flex-col gap-5" data-block-palette>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.PALETTE_HELP') }}
    </p>

    <section class="flex flex-col gap-2">
      <h4 class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.FREE_BLOCKS') }}
      </h4>
      <Draggable
        :list="freeTiles"
        item-key="id"
        :group="{ name: 'proposal-blocks', pull: 'clone', put: false }"
        :clone="toBlock"
        :sort="false"
        :move="onMove"
        class="grid grid-cols-2 gap-2"
      >
        <template #item="{ element }">
          <button
            type="button"
            :class="[
              TILE,
              full
                ? 'opacity-50 cursor-not-allowed outline-n-weak text-n-slate-10'
                : 'cursor-grab bg-n-solid-1 outline-n-weak text-n-slate-12 hover:outline-n-brand hover:text-n-blue-11',
            ]"
            :data-palette-tile="element.type"
            @click="add(element)"
          >
            <span class="i-lucide-grip-horizontal size-3.5 text-n-slate-9" />
            <span :class="BLOCK_INFO[element.type].icon" class="size-6 text-n-teal-10" />
            {{ name(element.type) }}
          </button>
        </template>
      </Draggable>
      <span v-if="full" class="text-xs text-n-amber-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.FULL', { max: MAX_BLOCKS }) }}
      </span>
    </section>

    <section class="flex flex-col gap-2">
      <h4 class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.PROPOSAL_BLOCKS') }}
      </h4>
      <Draggable
        :list="proposalTiles"
        item-key="id"
        :group="{ name: 'proposal-blocks', pull: 'clone', put: false }"
        :clone="toBlock"
        :sort="false"
        :move="onMove"
        class="grid grid-cols-2 gap-2"
      >
        <template #item="{ element }">
          <button
            v-tooltip.top="
              element.onSheet
                ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.ON_SHEET')
                : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.HIDDEN_TILE')
            "
            type="button"
            :class="[
              TILE,
              element.onSheet
                ? 'cursor-default bg-n-alpha-1 outline-transparent text-n-slate-10'
                : 'cursor-grab bg-n-solid-1 outline-dashed outline-n-slate-7 text-n-slate-12 hover:outline-n-brand hover:text-n-blue-11',
            ]"
            :data-palette-tile="element.type"
            @click="add(element)"
          >
            <span
              :class="[
                BLOCK_INFO[element.type]?.icon,
                { 'text-n-teal-10': !element.onSheet },
              ]"
              class="size-5"
            />
            {{ name(element.type) }}
            <span
              class="px-1.5 rounded-full text-[10px] font-normal"
              :class="
                element.onSheet
                  ? 'bg-n-alpha-2 text-n-slate-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                element.onSheet
                  ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.ON_SHEET_BADGE')
                  : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.HIDDEN_BADGE')
              }}
            </span>
          </button>
        </template>
      </Draggable>
    </section>
  </div>
</template>
