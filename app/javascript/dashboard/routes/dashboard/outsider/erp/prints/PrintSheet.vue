<script setup>
// OUTSIDER: a folha A4 do estúdio de modelos de relatório. Os blocos aparecem como vão sair no PDF (PrintBlock), com os
// dados de exemplo ou de uma OS/orçamento de verdade. Passar o mouse mostra o nome do bloco; clicar seleciona (os ajustes
// abrem ao lado); arrastar pela alça muda a ordem; um bloco da lista da esquerda pode ser solto em qualquer ponto.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import PrintBlock from './PrintBlock.vue';
import { BLOCK_ICONS, FONT_CSS, MARGINS, PAGE_WIDTH } from './printsHelpers';

const props = defineProps({
  content: { type: Object, required: true },
  catalog: { type: Object, required: true },
  values: { type: Object, default: null },
  images: { type: Object, default: () => ({}) },
  photos: { type: Object, default: () => ({}) },
  zoom: { type: Number, default: 1 },
});

const emit = defineEmits(['move', 'duplicate', 'remove', 'added']);

const blocks = defineModel('blocks', { type: Array, required: true });
const selectedId = defineModel('selectedId', { type: String, default: null });

const { t } = useI18n();

const theme = computed(() => props.content.theme || {});
const margin = computed(() => MARGINS[theme.value.margin] || 36);
const width = computed(() => PAGE_WIDTH - margin.value * 2);

const sheetStyle = computed(() => ({
  width: `${PAGE_WIDTH}px`,
  minHeight: '842px',
  padding: `${margin.value}px ${margin.value}px ${margin.value + 10}px`,
  fontFamily: FONT_CSS[theme.value.body_font] || FONT_CSS.helvetica,
  '--print-heading': FONT_CSS[theme.value.heading_font] || FONT_CSS.helvetica,
  zoom: props.zoom,
}));

const blockName = type => t(`OUTSIDER_ERP.PRINTS.BLOCKS.${type.toUpperCase()}`);

const act = (name, id) => {
  if (name === 'up') emit('move', id, -1);
  else if (name === 'down') emit('move', id, 1);
  else if (name === 'duplicate') emit('duplicate', id);
  else emit('remove', id);
};

const onChange = event => {
  if (event?.added) emit('added', event.added.element.id);
};

const GAP_SKIP = ['spacer', 'page_break'];
</script>

<template>
  <div
    class="relative bg-white shadow-lg rounded-sm text-[#1D2733] mx-auto"
    :style="sheetStyle"
    data-print-sheet
    @click.self="selectedId = null"
  >
    <Draggable
      v-model="blocks"
      item-key="id"
      handle="[data-drag-handle]"
      :group="{ name: 'print-blocks', pull: false, put: true }"
      :animation="150"
      ghost-class="print-ghost"
      class="flex flex-col min-h-[700px]"
      @change="onChange"
    >
      <template #item="{ element, index }">
        <div
          class="relative group/block"
          :style="{
            marginTop: index && !GAP_SKIP.includes(element.type) ? '10px' : '0',
          }"
          :data-block-id="element.id"
          @click.stop="selectedId = element.id"
        >
          <div
            class="absolute pointer-events-none -inset-1.5 rounded transition-colors"
            :class="
              selectedId === element.id
                ? 'outline outline-2 outline-[#2563eb]'
                : 'group-hover/block:outline group-hover/block:outline-1 group-hover/block:outline-dashed group-hover/block:outline-[#2563eb]/60'
            "
          />
          <div
            class="absolute z-10 items-center gap-1 -top-5 left-0 h-5 px-1.5 rounded-t text-[10px] font-medium text-white bg-[#2563eb] whitespace-nowrap"
            :class="
              selectedId === element.id
                ? 'flex'
                : 'hidden group-hover/block:flex'
            "
            :style="{ zoom: 1 / zoom }"
          >
            <span
              data-drag-handle
              class="i-lucide-grip-vertical size-3 cursor-grab"
              :title="t('OUTSIDER_ERP.PRINTS.CANVAS.DRAG')"
            />
            <span :class="BLOCK_ICONS[element.type]" class="size-3" />
            {{ blockName(element.type) }}
          </div>
          <div
            v-if="selectedId === element.id"
            class="absolute z-10 flex items-center gap-0.5 -top-5 right-0 h-5 px-0.5 rounded-t bg-[#2563eb]"
            :style="{ zoom: 1 / zoom }"
          >
            <button
              v-for="action in [
                {
                  name: 'up',
                  icon: 'i-lucide-arrow-up',
                  disabled: index === 0,
                },
                {
                  name: 'down',
                  icon: 'i-lucide-arrow-down',
                  disabled: index === blocks.length - 1,
                },
                { name: 'duplicate', icon: 'i-lucide-copy' },
                { name: 'remove', icon: 'i-lucide-trash-2' },
              ]"
              :key="action.name"
              type="button"
              class="flex items-center justify-center p-0 text-white rounded size-4 hover:bg-white/20 disabled:opacity-40"
              :disabled="action.disabled"
              :title="
                t(`OUTSIDER_ERP.PRINTS.CANVAS.${action.name.toUpperCase()}`)
              "
              @click.stop="act(action.name, element.id)"
            >
              <span :class="action.icon" class="size-3" />
            </button>
          </div>
          <PrintBlock
            :block="element"
            :content="content"
            :catalog="catalog"
            :values="values"
            :images="images"
            :photos="photos"
            :width="width"
          />
        </div>
      </template>
      <template #footer>
        <div
          v-if="!blocks.length"
          class="flex flex-col items-center justify-center gap-2 p-10 text-sm text-center rounded-lg outline-dashed outline-1 outline-n-slate-7 text-n-slate-10"
        >
          <span class="i-lucide-mouse-pointer-click size-6" />
          {{ t('OUTSIDER_ERP.PRINTS.CANVAS.EMPTY_SHEET') }}
        </div>
      </template>
    </Draggable>
  </div>
</template>

<style scoped>
:deep(.print-ghost) {
  opacity: 0.45;
  outline: 2px dashed #2563eb;
}
</style>
