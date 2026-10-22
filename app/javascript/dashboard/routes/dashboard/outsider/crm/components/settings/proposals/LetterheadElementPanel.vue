<script setup>
// OUTSIDER: propriedades do elemento solto escolhido no papel timbrado: texto (com negrito, destaque,
// cor, alinhamento e campos automáticos) ou imagem, posição e largura em mm e em quais páginas entra.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import {
  ELEMENT_SIZES,
  PAGE_HEIGHT_MM,
  PAGE_WIDTH_MM,
  clamp,
  round1,
} from './templateDesign';

defineProps({
  imageUrl: { type: String, default: '' },
  isUploading: { type: Boolean, default: false },
});

const emit = defineEmits(['remove', 'replaceImage']);

const element = defineModel('element', { type: Object, required: true });

const { t } = useI18n();

const pageOptions = computed(() =>
  ['all', 'first'].map(value => ({
    value,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.PAGES.${value.toUpperCase()}`
    ),
  }))
);

const ALIGNS = [
  { value: 'left', icon: 'i-lucide-align-left' },
  { value: 'center', icon: 'i-lucide-align-center' },
  { value: 'right', icon: 'i-lucide-align-right' },
];

const LIMITS = {
  x: [0, PAGE_WIDTH_MM],
  y: [0, PAGE_HEIGHT_MM],
  width: [5, PAGE_WIDTH_MM],
  size: [ELEMENT_SIZES.min, ELEMENT_SIZES.max],
};

const setNumber = (key, value) => {
  if (value === '' || Number.isNaN(Number(value))) return;
  element.value[key] = round1(clamp(value, ...LIMITS[key]));
};

const set = (key, value) => {
  element.value[key] = value;
};

const fieldClass =
  '!mb-0 w-full px-2.5 py-1.5 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand';
const toggleClass = on =>
  on
    ? 'bg-n-brand text-white outline-n-brand'
    : 'bg-n-solid-3 text-n-slate-11 outline-n-weak hover:text-n-slate-12';
</script>

<template>
  <div class="flex flex-col gap-3" data-element-panel>
    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{
          element.type === 'image'
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.IMAGE_ELEMENT')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.TEXT_ELEMENT')
        }}
      </span>
      <Button
        type="button"
        size="xs"
        variant="ghost"
        color="ruby"
        icon="i-lucide-trash-2"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.REMOVE')"
        @click="emit('remove')"
      />
    </div>

    <template v-if="element.type === 'text'">
      <label data-fields class="flex flex-col gap-1 text-sm">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.TEXT') }}
        </span>
        <textarea
          :value="element.text"
          rows="3"
          maxlength="1000"
          :class="fieldClass"
          class="resize-y"
          @input="set('text', $event.target.value)"
        />
      </label>
      <div class="flex flex-wrap items-end gap-2">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11 w-16">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.SIZE') }}
          <input
            :value="element.size"
            type="number"
            :min="ELEMENT_SIZES.min"
            :max="ELEMENT_SIZES.max"
            :class="fieldClass"
            @change="setNumber('size', $event.target.value)"
          />
        </label>
        <button
          v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.BOLD')"
          type="button"
          class="flex items-center justify-center rounded-lg size-8 outline outline-1 -outline-offset-1"
          :class="toggleClass(element.bold)"
          :aria-pressed="element.bold"
          :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.BOLD')"
          @click="set('bold', !element.bold)"
        >
          <span class="i-lucide-bold size-4" />
        </button>
        <button
          v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIGHLIGHT')"
          type="button"
          class="flex items-center justify-center rounded-lg size-8 outline outline-1 -outline-offset-1"
          :class="
            element.highlight
              ? 'bg-yellow-300 text-black outline-yellow-400'
              : toggleClass(false)
          "
          :aria-pressed="element.highlight"
          :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIGHLIGHT')"
          @click="set('highlight', !element.highlight)"
        >
          <span class="i-lucide-highlighter size-4" />
        </button>
        <label
          v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.COLOR')"
          class="relative flex items-center justify-center overflow-hidden rounded-lg cursor-pointer size-8 outline outline-1 -outline-offset-1 outline-n-weak"
          :style="{ backgroundColor: `#${element.color}` }"
        >
          <input
            :value="`#${element.color}`"
            type="color"
            class="absolute inset-0 opacity-0 cursor-pointer"
            :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.COLOR')"
            @input="set('color', $event.target.value.slice(1))"
          />
        </label>
        <div class="flex items-center gap-0.5">
          <button
            v-for="align in ALIGNS"
            :key="align.value"
            type="button"
            class="flex items-center justify-center rounded-lg size-8 outline outline-1 -outline-offset-1"
            :class="toggleClass(element.align === align.value)"
            :aria-pressed="element.align === align.value"
            :aria-label="align.value"
            @click="set('align', align.value)"
          >
            <span :class="align.icon" class="size-4" />
          </button>
        </div>
      </div>
    </template>

    <div v-else class="flex items-center gap-3">
      <div
        class="flex items-center justify-center w-20 h-14 p-1 overflow-hidden rounded-lg bg-n-alpha-black2"
      >
        <img
          v-if="imageUrl"
          :src="imageUrl"
          alt=""
          class="object-contain max-w-full max-h-full"
        />
      </div>
      <Button
        type="button"
        size="xs"
        variant="faded"
        color="slate"
        icon="i-lucide-upload"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.REPLACE_IMAGE')"
        :is-loading="isUploading"
        @click="emit('replaceImage')"
      />
    </div>

    <div class="grid grid-cols-3 gap-2">
      <label
        v-for="key in ['x', 'y', 'width']"
        :key="key"
        class="flex flex-col gap-1 text-xs text-n-slate-11"
      >
        {{
          t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.${key.toUpperCase()}`)
        }}
        <input
          :value="element[key]"
          type="number"
          step="any"
          :class="fieldClass"
          @change="setNumber(key, $event.target.value)"
        />
      </label>
    </div>
    <label class="flex flex-col gap-1 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.ELEMENT_PAGES') }}
      <Select
        :model-value="element.pages"
        :options="pageOptions"
        @update:model-value="value => set('pages', value)"
      />
    </label>
  </div>
</template>
