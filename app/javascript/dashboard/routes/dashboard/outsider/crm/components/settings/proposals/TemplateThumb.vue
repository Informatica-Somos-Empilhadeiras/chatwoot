<script setup>
// OUTSIDER: miniatura da primeira folha de um modelo na lista de modelos (Entrega 17), com o papel
// timbrado e os blocos como o editor desenha. Só para ver; clicar abre o editor.
import { computed, reactive } from 'vue';
import LetterheadCanvas from './LetterheadCanvas.vue';
import BlockPreview from './BlockPreview.vue';
import {
  PAGE_WIDTH_MM,
  PT_TO_MM,
  contentOf,
  fontCss,
  pagesOf,
  spaceBefore,
} from './templateDesign';
import { useTemplateImages } from './useTemplateImages';

const props = defineProps({
  template: { type: Object, required: true },
  width: { type: Number, default: 240 },
});

// desenha numa folha de 600 px e reduz, para o texto sair proporcional
const SHEET = 600;

const images = reactive(useTemplateImages(computed(() => props.template)));
const form = computed(() => contentOf(props.template));
const firstPage = computed(() => pagesOf(form.value.blocks)[0]);
const scale = SHEET / PAGE_WIDTH_MM;

const spacing = (block, index) =>
  index === 0
    ? null
    : { marginTop: `${spaceBefore(block.type) * PT_TO_MM * scale}px` };
</script>

<template>
  <div
    class="overflow-hidden text-left pointer-events-none select-none"
    :style="{ width: `${width}px`, height: `${width * 0.72}px` }"
    aria-hidden="true"
  >
    <div
      class="origin-top-left"
      :style="{
        width: `${SHEET}px`,
        transform: `scale(${width / SHEET})`,
        fontFamily: fontCss(form.layout.font),
      }"
    >
      <LetterheadCanvas
        :layout="form.layout"
        :header-url="images.headerUrl"
        :footer-url="images.footerUrl"
        :header-ratio="images.ratios.header"
        :footer-ratio="images.ratios.footer"
        :image-urls="images.imageUrls"
        :width="SHEET"
        :editable="false"
      >
        <div
          v-for="(block, index) in firstPage"
          :key="block.key"
          :style="spacing(block, index)"
        >
          <BlockPreview
            :form="form"
            :block="block"
            :scale="scale"
            :image-urls="images.imageUrls"
          />
        </div>
      </LetterheadCanvas>
    </div>
  </div>
</template>
