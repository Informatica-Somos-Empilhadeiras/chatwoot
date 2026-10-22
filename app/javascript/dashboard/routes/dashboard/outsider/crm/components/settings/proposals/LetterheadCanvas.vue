<script setup>
// OUTSIDER: folha A4 em escala para posicionar os elementos soltos do papel timbrado. Arrastar move o
// elemento, a alça da direita muda a largura e as setas do teclado ajustam de 1 em 1 mm (Shift: 5 mm).
// Mostra o cabeçalho, o rodapé e a área do conteúdo (margens) da página escolhida: a primeira ou as
// seguintes, já que cada item pode sair só na primeira. O PDF da prévia é a referência final.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ELEMENT_SIZES,
  PAGE_HEIGHT_MM,
  PAGE_WIDTH_MM,
  PT_TO_MM,
  clamp,
  fontCss,
  round1,
} from './templateDesign';

const props = defineProps({
  headerUrl: { type: String, default: '' },
  footerUrl: { type: String, default: '' },
  headerRatio: { type: Number, default: 0 },
  footerRatio: { type: Number, default: 0 },
  imageUrls: { type: Object, default: () => ({}) },
  page: { type: String, default: 'first' },
  width: { type: Number, default: 300 },
});

const layout = defineModel('layout', { type: Object, required: true });
const selectedId = defineModel('selected', { type: String, default: null });

const { t } = useI18n();

const scale = computed(() => props.width / PAGE_WIDTH_MM);
const px = mm => `${mm * scale.value}px`;
// o PDF põe o rodapé 14 pt acima da borda de baixo, deixando espaço para o número da página
const FOOTER_GAP_MM = 14 * PT_TO_MM;

const onPage = pages => props.page === 'first' || pages === 'all';
const showHeader = computed(
  () => !!props.headerUrl && onPage(layout.value.header_pages)
);
const showFooter = computed(
  () => !!props.footerUrl && onPage(layout.value.footer_pages)
);
const headerMm = computed(() =>
  showHeader.value ? PAGE_WIDTH_MM * props.headerRatio : 0
);
const footerMm = computed(() =>
  showFooter.value ? PAGE_WIDTH_MM * props.footerRatio : 0
);

const contentBox = computed(() => {
  const { side, top, bottom } = layout.value.margins;
  return {
    left: px(side),
    right: px(side),
    top: px(headerMm.value + Number(top)),
    bottom: px(footerMm.value + Number(bottom)),
  };
});

const visibleElements = computed(() =>
  layout.value.elements.filter(element => onPage(element.pages))
);

// **negrito** e ==destaque== viram estilo; campos {..} ficam como estão (o PDF troca pelo valor)
const parts = text =>
  String(text || '')
    .split(/(\*\*[^*]+\*\*|==[^=]+==)/)
    .filter(Boolean)
    .map(part => {
      if (part.startsWith('**') && part.endsWith('**')) {
        return { text: part.slice(2, -2), bold: true };
      }
      if (part.startsWith('==') && part.endsWith('==')) {
        return { text: part.slice(2, -2), highlight: true };
      }
      return { text: part };
    });

const textStyle = element => ({
  fontSize: px(
    clamp(element.size, ELEMENT_SIZES.min, ELEMENT_SIZES.max) * PT_TO_MM
  ),
  fontFamily: fontCss(layout.value.font),
  fontWeight: element.bold ? 700 : 400,
  color: `#${element.color || '000000'}`,
  textAlign: element.align,
  lineHeight: 1.15,
});

const startDrag = (event, element, mode) => {
  if (event.button !== 0) return;
  event.preventDefault();
  event.stopPropagation();
  selectedId.value = element.id;
  event.currentTarget.closest('[data-element]')?.focus();
  const start = {
    x: event.clientX,
    y: event.clientY,
    left: element.x,
    top: element.y,
    width: element.width,
  };
  const onMove = moveEvent => {
    const dx = (moveEvent.clientX - start.x) / scale.value;
    const dy = (moveEvent.clientY - start.y) / scale.value;
    if (mode === 'resize') {
      element.width = round1(
        clamp(start.width + dx, 5, PAGE_WIDTH_MM - element.x)
      );
      return;
    }
    element.x = round1(clamp(start.left + dx, 0, PAGE_WIDTH_MM - 5));
    element.y = round1(clamp(start.top + dy, 0, PAGE_HEIGHT_MM - 3));
  };
  const onUp = () => {
    window.removeEventListener('pointermove', onMove);
    window.removeEventListener('pointerup', onUp);
  };
  window.addEventListener('pointermove', onMove);
  window.addEventListener('pointerup', onUp);
};

const KEYS = {
  ArrowLeft: [-1, 0],
  ArrowRight: [1, 0],
  ArrowUp: [0, -1],
  ArrowDown: [0, 1],
};

const onKeydown = (event, element) => {
  const step = KEYS[event.key];
  if (!step) return;
  event.preventDefault();
  const amount = event.shiftKey ? 5 : 1;
  element.x = round1(clamp(element.x + step[0] * amount, 0, PAGE_WIDTH_MM - 5));
  element.y = round1(
    clamp(element.y + step[1] * amount, 0, PAGE_HEIGHT_MM - 3)
  );
};
</script>

<template>
  <div
    class="relative overflow-hidden bg-white shadow-md select-none shrink-0 ring-1 ring-n-weak"
    :style="{ width: px(PAGE_WIDTH_MM), height: px(PAGE_HEIGHT_MM) }"
    data-letterhead-canvas
    @pointerdown="selectedId = null"
  >
    <img
      v-if="showHeader"
      :src="headerUrl"
      alt=""
      class="absolute top-0 left-0 w-full pointer-events-none"
      draggable="false"
    />
    <img
      v-if="showFooter"
      :src="footerUrl"
      alt=""
      class="absolute left-0 w-full pointer-events-none"
      :style="{ bottom: px(FOOTER_GAP_MM) }"
      draggable="false"
    />
    <!-- área do conteúdo (blocos) -->
    <div
      class="absolute flex flex-col gap-1.5 p-1.5 border border-dashed pointer-events-none border-slate-300"
      :style="contentBox"
    >
      <span class="text-[9px] uppercase tracking-wide text-slate-400">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.CONTENT_AREA') }}
      </span>
      <span
        v-for="line in 6"
        :key="line"
        class="h-1 rounded bg-slate-200"
        :style="{ width: `${100 - ((line * 13) % 40)}%` }"
      />
    </div>
    <span
      class="absolute text-[8px] text-slate-500 pointer-events-none"
      :style="{ right: px(layout.margins.side), bottom: px(2) }"
    >
      {{ page === 'first' ? '1 / 2' : '2 / 2' }}
    </span>

    <div
      v-for="element in visibleElements"
      :key="element.id"
      data-element
      :data-element-id="element.id"
      tabindex="0"
      class="absolute cursor-move group focus:outline-none"
      :class="
        selectedId === element.id
          ? 'ring-2 ring-n-brand z-10'
          : 'ring-1 ring-transparent hover:ring-n-blue-8'
      "
      :style="{
        left: px(element.x),
        top: px(element.y),
        width: px(element.width),
      }"
      @pointerdown="startDrag($event, element, 'move')"
      @keydown="onKeydown($event, element)"
    >
      <img
        v-if="element.type === 'image'"
        :src="imageUrls[element.image_id]"
        alt=""
        class="block w-full pointer-events-none"
        draggable="false"
      />
      <div
        v-else
        class="whitespace-pre-wrap break-words min-h-[6px]"
        :style="textStyle(element)"
      >
        <template v-for="(part, index) in parts(element.text)" :key="index">
          <span
            :class="{ 'font-bold': part.bold || element.bold }"
            :style="
              part.highlight || element.highlight
                ? { backgroundColor: '#ffff00' }
                : null
            "
            >{{ part.text }}</span
          >
        </template>
        <span v-if="!element.text" class="italic text-slate-400">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.EMPTY_TEXT') }}
        </span>
      </div>
      <span
        v-if="selectedId === element.id"
        class="absolute top-1/2 -right-1.5 w-2.5 h-5 -translate-y-1/2 rounded-sm cursor-ew-resize bg-n-brand"
        data-resize
        @pointerdown="startDrag($event, element, 'resize')"
      />
    </div>
  </div>
</template>
