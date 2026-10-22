<script setup>
// OUTSIDER: um bloco do conteúdo do modelo. Fechado, mostra o nome, se começa em página nova e o olho
// para esconder; aberto, o estilo do bloco (página nova, tamanho, negrito, destaque) e os textos dele.
// Os textos dos blocos padrão são as chaves de sempre do modelo (form); o bloco de texto livre guarda
// título e texto nele mesmo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConditionsEditor from './ConditionsEditor.vue';
import { MAX_TEXT } from './proposalSettings';
import { BLOCK_INFO, BLOCK_SIZES } from './templateDesign';

defineProps({
  expanded: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle', 'remove']);

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

// o título do bloco de texto livre ajuda a achar o bloco na lista
const subtitle = computed(() =>
  block.value.type === 'text'
    ? block.value.heading || block.value.text.slice(0, 60)
    : t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HELP.${typeKey.value}`)
);

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
  <div
    class="rounded-xl outline outline-1 -outline-offset-1 bg-n-solid-1"
    :class="[
      expanded ? 'outline-n-brand' : 'outline-n-container',
      { 'opacity-60': !block.visible },
    ]"
    :data-block="block.key"
  >
    <div class="flex items-center gap-2 px-2 py-2">
      <span
        class="flex items-center justify-center rounded cursor-grab size-6 text-n-slate-10 hover:text-n-slate-12 crm-block-handle"
        :title="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.DRAG')"
      >
        <span class="i-lucide-grip-vertical size-4" />
      </span>
      <button
        type="button"
        class="flex items-center flex-1 min-w-0 gap-2 text-left"
        @click="emit('toggle')"
      >
        <span :class="info.icon" class="size-4 shrink-0 text-n-slate-11" />
        <span class="flex flex-col min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ name }}
          </span>
          <span v-if="subtitle" class="text-xs truncate text-n-slate-11">
            {{ subtitle }}
          </span>
        </span>
      </button>
      <span
        v-if="block.new_page"
        class="px-1.5 py-0.5 text-[11px] rounded-md bg-n-alpha-2 text-n-slate-11 whitespace-nowrap"
      >
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.NEW_PAGE_BADGE') }}
      </span>
      <Button
        v-tooltip.top="
          block.visible
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIDE')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.SHOW')
        "
        type="button"
        size="xs"
        variant="ghost"
        color="slate"
        :icon="block.visible ? 'i-lucide-eye' : 'i-lucide-eye-off'"
        :aria-label="
          block.visible
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIDE')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.SHOW')
        "
        @click="set('visible', !block.visible)"
      />
      <Button
        type="button"
        size="xs"
        variant="ghost"
        color="slate"
        :icon="expanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        :aria-label="name"
        @click="emit('toggle')"
      />
    </div>

    <div
      v-if="expanded"
      class="flex flex-col gap-4 px-3 pt-1 pb-3 border-t border-n-weak"
    >
      <!-- Estilo do bloco -->
      <div class="flex flex-wrap items-center gap-x-4 gap-y-2 pt-3">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch
            :model-value="block.new_page"
            @update:model-value="value => set('new_page', value)"
          />
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.NEW_PAGE') }}
        </label>
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
      <div v-if="block.type === 'specs'" class="grid gap-3 sm:grid-cols-2">
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
        <div>
          <Button
            type="button"
            size="xs"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.REMOVE')"
            @click="emit('remove')"
          />
        </div>
      </template>
    </div>
  </div>
</template>
