<script setup>
// OUTSIDER: ajustes do bloco selecionado na folha, na esquerda do editor (Entregas 16 e 17): página nova,
// estilo (tamanho, negrito, destaque) e os textos do bloco. Os textos dos blocos da proposta são as chaves
// de sempre do modelo (form); os blocos livres guardam o que é deles (texto e título, imagem com largura e
// alinhamento, cor e espessura da linha, altura do espaço).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConditionsEditor from './ConditionsEditor.vue';
import { MAX_TEXT } from './proposalSettings';
import {
  BLOCK_INFO,
  BLOCK_SIZES,
  DIVIDER_THICKNESS,
  IMAGE_WIDTHS,
  SPACER_HEIGHTS,
  clamp,
  isFree,
  round1,
} from './templateDesign';

defineProps({
  imageUrl: { type: String, default: '' },
  isUploading: { type: Boolean, default: false },
});

const emit = defineEmits(['back', 'remove', 'hide', 'pickImage']);

const block = defineModel('block', { type: Object, required: true });
const form = defineModel('form', { type: Object, required: true });

const { t } = useI18n();

const MULTILINE = [
  'intro',
  'parties_text',
  'acceptance_text',
  'closing',
  'signature_box',
];

const info = computed(() => BLOCK_INFO[block.value.type] || BLOCK_INFO.text);
const typeKey = computed(() => block.value.type.toUpperCase());

const name = computed(() =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.TYPES.${typeKey.value}`)
);

const help = computed(() =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HELP.${typeKey.value}`)
);

// imagem, linha e espaço não têm texto: sem tamanho, negrito e destaque
const hasText = computed(
  () => !['image', 'divider', 'spacer'].includes(block.value.type)
);

const ALIGNS = [
  { value: 'left', icon: 'i-lucide-align-left' },
  { value: 'center', icon: 'i-lucide-align-center' },
  { value: 'right', icon: 'i-lucide-align-right' },
];

const THICKNESSES = [0.5, 1, 1.5, 2, 3, 4];
const thicknessOptions = computed(() =>
  THICKNESSES.map(value => ({
    value,
    label: `${String(value).replace('.', ',')} pt`,
  }))
);

const setNumber = (key, value, limits) => {
  if (value === '' || Number.isNaN(Number(value))) return;
  set(key, round1(clamp(value, limits.min, limits.max)));
};

const sizeOptions = computed(() =>
  Array.from({ length: BLOCK_SIZES.max - BLOCK_SIZES.min + 1 }, (_, i) => {
    const size = BLOCK_SIZES.min + i;
    return { value: size, label: `${size} pt` };
  })
);

const sideOptions = computed(() =>
  ['right', 'left'].map(side => ({
    value: side,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.IMAGE_SIDES.${side.toUpperCase()}`
    ),
  }))
);

const styleOptions = computed(() =>
  ['table', 'list'].map(style => ({
    value: style,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.STYLES.${style.toUpperCase()}`
    ),
  }))
);

const set = (key, value) => {
  block.value = { ...block.value, [key]: value };
};

const textLabel = key =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.TEXTS.${key.toUpperCase()}`);
const textHelp = key =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.TEXTS_HELP.${key.toUpperCase()}`);

const fieldClass =
  '!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand placeholder:text-n-slate-10';
const toggleClass = on =>
  on
    ? 'bg-n-brand text-white outline-n-brand'
    : 'bg-n-solid-3 text-n-slate-11 outline-n-weak hover:text-n-slate-12';
</script>

<template>
  <div class="flex flex-col gap-4" :data-block-settings="block.key">
    <button
      type="button"
      class="flex items-center gap-1 text-xs font-medium w-fit text-n-blue-11 hover:underline"
      data-settings-back
      @click="emit('back')"
    >
      <span class="i-lucide-arrow-left size-3.5" />
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.BACK_TO_BLOCKS') }}
    </button>
    <div class="flex items-start gap-2">
      <span
        :class="info.icon"
        class="mt-0.5 size-5 shrink-0 text-n-teal-10"
      />
      <div class="flex flex-col min-w-0">
        <span class="text-sm font-semibold text-n-slate-12">{{ name }}</span>
        <span v-if="help" class="text-xs text-n-slate-11">{{ help }}</span>
      </div>
    </div>

    <div class="flex flex-col gap-4">
      <!-- Estilo do bloco -->
      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <Switch
          :model-value="block.new_page"
          @update:model-value="value => set('new_page', value)"
        />
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.NEW_PAGE') }}
      </label>
      <div v-if="hasText" class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.SIZE') }}
          <Select
            :model-value="block.size"
            :options="sizeOptions"
            @update:model-value="value => set('size', Number(value))"
          />
        </label>
        <div class="flex items-center gap-1">
          <button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.BOLD')"
            type="button"
            class="flex items-center justify-center rounded-lg size-8 outline outline-1 -outline-offset-1"
            :class="toggleClass(block.bold)"
            :aria-pressed="block.bold"
            :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.BOLD')"
            @click="set('bold', !block.bold)"
          >
            <span class="i-lucide-bold size-4" />
          </button>
          <button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIGHLIGHT')"
            type="button"
            class="flex items-center justify-center rounded-lg size-8 outline outline-1 -outline-offset-1"
            :class="
              block.highlight
                ? 'bg-yellow-300 text-black outline-yellow-400'
                : toggleClass(false)
            "
            :aria-pressed="block.highlight"
            :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIGHLIGHT')"
            @click="set('highlight', !block.highlight)"
          >
            <span class="i-lucide-highlighter size-4" />
          </button>
        </div>
      </div>

      <!-- Características das máquinas -->
      <div v-if="block.type === 'specs'" class="grid gap-3">
        <label data-fields class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HEADING') }}
          </span>
          <input
            :value="block.heading"
            type="text"
            maxlength="200"
            :class="fieldClass"
            @input="set('heading', $event.target.value)"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.IMAGE_SIDE') }}
          </span>
          <Select
            :model-value="block.image_side"
            :options="sideOptions"
            @update:model-value="value => set('image_side', value)"
          />
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch
            :model-value="block.equipment"
            @update:model-value="value => set('equipment', value)"
          />
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.EQUIPMENT') }}
        </label>
        <label
          v-if="block.equipment"
          data-fields
          class="flex flex-col gap-1 text-sm"
        >
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.EQUIPMENT_HEADING') }}
          </span>
          <input
            :value="block.equipment_heading"
            type="text"
            maxlength="200"
            :class="fieldClass"
            @input="set('equipment_heading', $event.target.value)"
          />
        </label>
      </div>

      <!-- Itens -->
      <label
        v-if="block.type === 'items'"
        class="flex items-start gap-3 text-sm text-n-slate-12"
      >
        <Switch v-model="form.show_discount" class="mt-0.5" />
        <span class="flex flex-col gap-0.5">
          {{
            t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FLAGS.SHOW_DISCOUNT')
          }}
          <span class="text-xs text-n-slate-11">
            {{
              t(
                'OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FLAGS_HELP.SHOW_DISCOUNT'
              )
            }}
          </span>
        </span>
      </label>

      <!-- Condições -->
      <template v-if="block.type === 'conditions'">
        <div class="flex flex-wrap items-start gap-4">
          <label class="flex flex-col gap-1 text-sm">
            <span class="font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.STYLE') }}
            </span>
            <Select v-model="form.conditions_style" :options="styleOptions" />
          </label>
          <label
            v-if="form.conditions_style === 'list'"
            data-fields
            class="flex flex-col flex-1 gap-1 text-sm min-w-[12rem]"
          >
            <span class="font-medium text-n-slate-12">
              {{ textLabel('conditions_heading') }}
            </span>
            <input
              v-model="form.conditions_heading"
              type="text"
              :maxlength="MAX_TEXT"
              :class="fieldClass"
            />
          </label>
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.HELP') }}
        </p>
        <ConditionsEditor v-model="form.conditions" />
      </template>

      <!-- Textos padrão do bloco -->
      <label
        v-for="key in info.texts"
        :key="key"
        data-fields
        class="flex flex-col gap-1 text-sm"
      >
        <span class="font-medium text-n-slate-12">{{ textLabel(key) }}</span>
        <textarea
          v-if="MULTILINE.includes(key)"
          v-model="form[key]"
          rows="3"
          :maxlength="MAX_TEXT"
          :class="fieldClass"
        />
        <input
          v-else
          v-model="form[key]"
          type="text"
          :maxlength="MAX_TEXT"
          :class="fieldClass"
        />
        <span class="text-xs text-n-slate-11">{{ textHelp(key) }}</span>
      </label>

      <!-- Texto livre -->
      <template v-if="block.type === 'text'">
        <label data-fields class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HEADING') }}
          </span>
          <input
            :value="block.heading"
            type="text"
            maxlength="200"
            :placeholder="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HEADING_PLACEHOLDER')
            "
            :class="fieldClass"
            @input="set('heading', $event.target.value)"
          />
        </label>
        <label data-fields class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.TEXT') }}
          </span>
          <textarea
            :value="block.text"
            rows="4"
            :maxlength="MAX_TEXT"
            :class="fieldClass"
            @input="set('text', $event.target.value)"
          />
        </label>
      </template>

      <!-- Imagem -->
      <template v-if="block.type === 'image'">
        <div class="flex flex-col gap-2">
          <img
            v-if="imageUrl"
            :src="imageUrl"
            alt=""
            class="object-contain w-full rounded-lg max-h-32 bg-n-alpha-1"
          />
          <Button
            type="button"
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-image-plus"
            :label="
              imageUrl
                ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.REPLACE_IMAGE')
                : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.PICK_IMAGE')
            "
            :is-loading="isUploading"
            data-image-pick
            @click="emit('pickImage')"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.IMAGE_HELP') }}
          </span>
        </div>
        <label class="flex flex-col gap-1 text-sm">
          <span class="flex justify-between font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.IMAGE_WIDTH') }}
            <span class="font-normal tabular-nums text-n-slate-11">
              {{ `${block.width}%` }}
            </span>
          </span>
          <input
            :value="block.width"
            type="range"
            :min="IMAGE_WIDTHS.min"
            :max="IMAGE_WIDTHS.max"
            step="1"
            class="w-full accent-n-brand"
            data-image-width
            @input="setNumber('width', $event.target.value, IMAGE_WIDTHS)"
          />
        </label>
        <div class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.ALIGN') }}
          </span>
          <div class="flex gap-1">
            <button
              v-for="align in ALIGNS"
              :key="align.value"
              type="button"
              class="flex items-center justify-center rounded-lg size-8 outline outline-1 -outline-offset-1"
              :class="toggleClass(block.align === align.value)"
              :aria-pressed="block.align === align.value"
              @click="set('align', align.value)"
            >
              <span :class="align.icon" class="size-4" />
            </button>
          </div>
        </div>
      </template>

      <!-- Linha -->
      <div v-if="block.type === 'divider'" class="flex flex-wrap gap-4">
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.LINE_COLOR') }}
          </span>
          <input
            :value="`#${block.color}`"
            type="color"
            class="w-16 h-9 p-0.5 rounded-lg cursor-pointer bg-n-alpha-black2 outline outline-1 -outline-offset-1 outline-n-weak"
            @input="set('color', $event.target.value.slice(1).toUpperCase())"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.LINE_THICKNESS') }}
          </span>
          <Select
            :model-value="block.thickness"
            :options="thicknessOptions"
            @update:model-value="
              value => setNumber('thickness', value, DIVIDER_THICKNESS)
            "
          />
        </label>
      </div>

      <!-- Espaço -->
      <label
        v-if="block.type === 'spacer'"
        class="flex flex-col gap-1 text-sm"
      >
        <span class="flex justify-between font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.SPACER_HEIGHT') }}
          <span class="font-normal tabular-nums text-n-slate-11">
            {{ `${block.height} mm` }}
          </span>
        </span>
        <input
          :value="block.height"
          type="range"
          :min="SPACER_HEIGHTS.min"
          :max="SPACER_HEIGHTS.max"
          step="1"
          class="w-full accent-n-brand"
          @input="setNumber('height', $event.target.value, SPACER_HEIGHTS)"
        />
      </label>

      <div class="pt-3 border-t border-n-weak">
        <Button
          v-if="isFree(block)"
          type="button"
          size="xs"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.REMOVE')"
          @click="emit('remove')"
        />
        <Button
          v-else
          type="button"
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-eye-off"
          :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIDE')"
          @click="emit('hide')"
        />
      </div>
    </div>
  </div>
</template>
