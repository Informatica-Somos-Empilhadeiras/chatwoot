<script setup>
// OUTSIDER: as folhas do modelo no centro do editor (Entrega 17): o papel timbrado e os blocos visíveis
// em sequência, uma folha por "página nova". Em Blocos, arrastar pela etiqueta muda a ordem (também de
// uma folha para outra), soltar um bloco da lista da esquerda coloca ele ali e clicar seleciona. Em Papel
// timbrado, os blocos ficam apagados e os elementos soltos é que se arrastam.
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import LetterheadCanvas from './LetterheadCanvas.vue';
import CanvasBlock from './CanvasBlock.vue';
import BlockPreview from './BlockPreview.vue';
import {
  BLOCK_INFO,
  PT_TO_MM,
  PAGE_WIDTH_MM,
  blocksFromPages,
  isFree,
  pagesOf,
  spaceBefore,
} from './templateDesign';

const props = defineProps({
  images: { type: Object, required: true },
  mode: { type: String, default: 'blocks' },
  width: { type: Number, default: 680 },
  uploadingKey: { type: String, default: null },
  fontCss: { type: String, default: '' },
});

const emit = defineEmits([
  'move',
  'duplicate',
  'hide',
  'remove',
  'pickImage',
  'upload',
  'added',
]);

const blocks = defineModel('blocks', { type: Array, required: true });
const form = defineModel('form', { type: Object, required: true });
const layout = defineModel('layout', { type: Object, required: true });
const selectedKey = defineModel('selectedKey', { type: String, default: null });
const selectedElement = defineModel('selectedElement', {
  type: String,
  default: null,
});

const { t } = useI18n();

const scale = computed(() => props.width / PAGE_WIDTH_MM);
const isBlocks = computed(() => props.mode === 'blocks');

// listas das folhas: o vuedraggable mexe nelas no lugar; depois do soltar, viram a lista do modelo
const pages = ref([]);
watch(
  blocks,
  list => {
    pages.value = pagesOf(list);
  },
  { immediate: true }
);

let pending = false;
const onChange = event => {
  if (event?.added) emit('added', event.added.element.key);
  if (pending) return;
  pending = true;
  // soltar em outra folha dispara a saída de uma lista e a entrada na outra: junta as duas
  nextTick(() => {
    pending = false;
    blocks.value = blocksFromPages(pages.value, blocks.value);
  });
};

const flat = computed(() => pages.value.flat());
const positionOf = key => flat.value.findIndex(block => block.key === key);

const blockName = block =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.TYPES.${block.type.toUpperCase()}`);

const spacing = (block, index) =>
  index === 0
    ? null
    : { marginTop: `${spaceBefore(block.type) * PT_TO_MM * scale.value}px` };

const replace = block => {
  blocks.value = blocks.value.map(item => (item.key === block.key ? block : item));
};

const select = key => {
  if (isBlocks.value) selectedKey.value = key;
};

const onSheetClick = () => {
  if (isBlocks.value) selectedKey.value = null;
};
</script>

<template>
  <div
    class="flex flex-col items-center gap-8"
    :style="{ fontFamily: fontCss }"
    data-proposal-canvas
  >
    <div
      v-for="(list, pageIndex) in pages"
      :key="pageIndex"
      class="flex flex-col items-center gap-1.5"
    >
      <span class="text-xs text-n-slate-10">
        {{
          t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.PAGE', {
            page: pageIndex + 1,
            total: pages.length,
          })
        }}
      </span>
      <LetterheadCanvas
        v-model:layout="layout"
        v-model:selected="selectedElement"
        :header-url="images.headerUrl"
        :footer-url="images.footerUrl"
        :header-ratio="images.ratios.header"
        :footer-ratio="images.ratios.footer"
        :image-urls="images.imageUrls"
        :page-number="pageIndex + 1"
        :page-count="pages.length"
        :width="width"
        :editable="!isBlocks"
        @click="onSheetClick"
      >
        <div
          v-if="pageIndex > 0"
          class="text-right text-[#000]"
          :style="{
            fontSize: `${9 * PT_TO_MM * scale}px`,
            marginBottom: `${2 * PT_TO_MM * scale}px`,
          }"
        >
          <b>{{ 'PROPOSTA' }}</b>
          <span
            class="inline-block px-1 mx-px rounded bg-[#dbeafe] text-[#1e40af] text-[0.85em]"
            >{{ 'proposta.numero' }}</span
          >
        </div>
        <Draggable
          :list="list"
          item-key="key"
          group="proposal-blocks"
          handle=".crm-canvas-handle"
          :animation="150"
          :disabled="!isBlocks"
          ghost-class="crm-canvas-ghost"
          class="flex flex-col min-h-[6rem]"
          :class="{ 'opacity-40 pointer-events-none': !isBlocks }"
          :data-page="pageIndex + 1"
          @change="onChange"
        >
          <template #item="{ element, index }">
            <CanvasBlock
              :name="blockName(element)"
              :icon="BLOCK_INFO[element.type]?.icon"
              :selected="isBlocks && selectedKey === element.key"
              :free="isFree(element)"
              :first="positionOf(element.key) === 0"
              :last="positionOf(element.key) === flat.length - 1"
              :new-page="pageIndex > 0 && index === 0"
              :style="spacing(element, index)"
              :data-block="element.key"
              @select="select(element.key)"
              @move="direction => emit('move', element.key, direction)"
              @duplicate="emit('duplicate', element.key)"
              @hide="emit('hide', element.key)"
              @remove="emit('remove', element.key)"
            >
              <BlockPreview
                v-model:form="form"
                :block="element"
                :scale="scale"
                :image-urls="images.imageUrls"
                :editing="isBlocks && selectedKey === element.key"
                :is-uploading="uploadingKey === element.key"
                @update:block="replace"
                @pick-image="emit('pickImage', element.key)"
                @upload="file => emit('upload', element.key, file)"
              />
            </CanvasBlock>
          </template>
          <template v-if="!list.length" #footer>
            <div
              class="flex flex-col items-center justify-center flex-1 gap-1 p-6 text-sm text-center border border-dashed rounded-lg border-slate-300 text-slate-500"
            >
              <span class="i-lucide-mouse-pointer-click size-5" />
              {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.EMPTY_PAGE') }}
            </div>
          </template>
        </Draggable>
      </LetterheadCanvas>
    </div>
  </div>
</template>

<style scoped>
:deep(.crm-canvas-ghost) {
  @apply opacity-60 outline outline-2 outline-dashed outline-n-brand rounded-sm;
}
</style>
