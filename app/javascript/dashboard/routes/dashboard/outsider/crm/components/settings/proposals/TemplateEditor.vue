<script setup>
// OUTSIDER: editor de um modelo de proposta (Entrega 16). Em cima, nome, ativo, fonte e validade; em
// Conteúdo, os blocos do PDF em sequência (ordem, mostrar ou esconder, estilo e textos de cada um); em
// Papel timbrado, cabeçalho, rodapé, margens e os elementos soltos arrastáveis. Ao lado, a prévia do PDF
// com o que está na tela. Salvar manda só as chaves do conteúdo que mudaram (o servidor junta com o resto).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import FieldChips from './FieldChips.vue';
import TemplateBlocks from './TemplateBlocks.vue';
import LetterheadSettings from './LetterheadSettings.vue';
import TemplatePreview from './TemplatePreview.vue';
import {
  FLAG_KEYS,
  TEXT_KEYS,
  conditionRow,
  settingsError,
} from './proposalSettings';
import { FLAG_OF_BLOCK, FONTS, blocksOf, layoutOf } from './templateDesign';

const props = defineProps({
  template: { type: Object, required: true },
  visible: { type: Boolean, default: true },
});

const emit = defineEmits(['updated', 'dirty']);

const { t } = useI18n();

const CONTENT_KEYS = [
  ...TEXT_KEYS,
  ...FLAG_KEYS,
  'validity_days',
  'conditions_style',
  'conditions',
  'blocks',
  'layout',
];

// conteúdo do modelo no formato do formulário (textos vazios, chaves desligadas)
const contentOf = template => {
  const content = template.content || {};
  return {
    ...Object.fromEntries(TEXT_KEYS.map(key => [key, content[key] ?? ''])),
    ...Object.fromEntries(FLAG_KEYS.map(key => [key, content[key] === true])),
    validity_days: Number(content.validity_days ?? 0),
    conditions_style: content.conditions_style === 'list' ? 'list' : 'table',
    conditions: (content.conditions || []).map(conditionRow),
    blocks: blocksOf(content),
    layout: layoutOf(content),
  };
};

const name = ref('');
const active = ref(true);
const form = ref({});
const tab = ref('content');
const showPreview = ref(true);
const isSaving = ref(false);

const reset = () => {
  name.value = props.template.name;
  active.value = props.template.active;
  form.value = contentOf(props.template);
};
reset();

const original = computed(() => contentOf(props.template));

// condições sem o uid; números como número
const plain = (key, value) => {
  if (key === 'conditions') {
    return value.map(row => ({ label: row.label, text: row.text }));
  }
  if (key === 'validity_days') return Number(value);
  return value;
};

const changedKeys = computed(() =>
  CONTENT_KEYS.filter(
    key =>
      JSON.stringify(plain(key, form.value[key])) !==
      JSON.stringify(plain(key, original.value[key]))
  )
);

const isDirty = computed(
  () =>
    name.value.trim() !== props.template.name ||
    active.value !== props.template.active ||
    changedKeys.value.length > 0
);

watch(isDirty, dirty => emit('dirty', dirty));

const validityValid = computed(() => {
  const days = form.value.validity_days;
  return (
    days !== '' && Number.isInteger(Number(days)) && days >= 0 && days <= 365
  );
});
const hasVisibleBlock = computed(() =>
  form.value.blocks.some(block => block.visible)
);
const isValid = computed(
  () => !!name.value.trim() && validityValid.value && hasVisibleBlock.value
);

const fontOptions = computed(() =>
  FONTS.map(font => ({
    value: font.value,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FONTS.${font.value.toUpperCase().replace('-', '_')}`
    ),
  }))
);

const font = computed({
  get: () => form.value.layout.font,
  set: value => {
    form.value.layout = { ...form.value.layout, font: value };
  },
});

// blocos que eram ligados pelas chaves antigas levam a chave junto, para o modelo ficar coerente
const flagsFromBlocks = () =>
  Object.fromEntries(
    Object.entries(FLAG_OF_BLOCK).map(([type, flag]) => [
      flag,
      form.value.blocks.some(block => block.type === type && block.visible),
    ])
  );

const contentPayload = keys => {
  const content = Object.fromEntries(
    keys.map(key => [key, plain(key, form.value[key])])
  );
  return keys.includes('blocks')
    ? { ...content, ...flagsFromBlocks() }
    : content;
};

const previewPayload = computed(() => ({
  name: name.value.trim() || props.template.name,
  active: true,
  content: contentPayload(CONTENT_KEYS),
}));

// campo automático vai para o texto em edição; sem nenhum em edição, é copiado
let lastField = null;
const onFocusIn = event => {
  const field = event.target;
  if (
    ['INPUT', 'TEXTAREA'].includes(field.tagName) &&
    field.closest('[data-fields]')
  ) {
    lastField = field;
  }
};

const insertField = async token => {
  if (lastField?.isConnected && !lastField.disabled) {
    const start = lastField.selectionStart ?? lastField.value.length;
    const end = lastField.selectionEnd ?? start;
    lastField.setRangeText(token, start, end, 'end');
    lastField.dispatchEvent(new Event('input', { bubbles: true }));
    lastField.focus();
    return;
  }
  try {
    await copyTextToClipboard(token);
    useAlert(
      t('OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.COPIED', { field: token })
    );
  } catch {
    useAlert(token);
  }
};

// imagem enviada (cabeçalho, rodapé) volta com o modelo salvo; o que está em edição continua na tela
const onImageUpdated = data => emit('updated', data);

const save = async () => {
  if (!isValid.value || !isDirty.value) return;
  const payload = { name: name.value.trim(), active: active.value };
  if (changedKeys.value.length) {
    payload.content = contentPayload(changedKeys.value);
  }
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalTemplate(
      props.template.id,
      payload
    );
    emit('updated', data);
    // a resposta já vem normalizada (linhas vazias de condição saem, números dentro dos limites)
    name.value = data.name;
    active.value = data.active;
    form.value = contentOf(data);
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.SAVED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};

const TABS = [
  { key: 'content', icon: 'i-lucide-list-ordered' },
  { key: 'letterhead', icon: 'i-lucide-layout-template' },
];
</script>

<template>
  <form
    novalidate
    class="flex flex-col gap-5 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
    @submit.prevent="save"
    @focusin="onFocusIn"
  >
    <!-- Nome, ativo, fonte e validade -->
    <div class="flex flex-wrap items-start gap-4">
      <Input
        v-model="name"
        maxlength="255"
        class="flex-1 min-w-[14rem]"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.NAME')"
        :message-type="name.trim() ? 'info' : 'error'"
      />
      <label class="flex flex-col gap-1 text-sm">
        <span class="mb-0.5 font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FONT') }}
        </span>
        <Select v-model="font" :options="fontOptions" />
      </label>
      <Input
        v-model="form.validity_days"
        v-tooltip.top="
          t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY_HELP')
        "
        type="number"
        min="0"
        max="365"
        class="w-32"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY')"
        :message-type="validityValid ? 'info' : 'error'"
      />
      <div class="flex items-center gap-3 pt-7">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="active" />
          {{ t('OUTSIDER_CRM.SETTINGS.ACTIVE') }}
        </label>
        <Label
          :label="
            t(
              `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.KINDS.${template.kind.toUpperCase()}`
            )
          "
          compact
        />
      </div>
    </div>
    <p v-if="!active" class="mb-0 -mt-3 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.INACTIVE_HELP') }}
    </p>

    <div
      class="grid items-start gap-4"
      :class="{
        'xl:grid-cols-[minmax(0,1fr)_minmax(0,25rem)]': showPreview,
      }"
    >
      <div class="flex flex-col min-w-0 gap-4">
        <div class="flex items-center justify-between gap-2">
          <nav class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-1">
            <button
              v-for="item in TABS"
              :key="item.key"
              type="button"
              class="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-md"
              :class="
                tab === item.key
                  ? 'bg-n-solid-3 text-n-slate-12 font-medium shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="tab = item.key"
            >
              <span :class="item.icon" class="size-4" />
              {{
                t(
                  `OUTSIDER_CRM.PROPOSAL_SETTINGS.EDITOR_TABS.${item.key.toUpperCase()}`
                )
              }}
            </button>
          </nav>
          <Button
            v-if="!showPreview"
            type="button"
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-file-text"
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.SHOW')"
            @click="showPreview = true"
          />
        </div>

        <template v-if="tab === 'content'">
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.DESCRIPTION') }}
          </p>
          <FieldChips @insert="insertField" />
          <TemplateBlocks v-model:blocks="form.blocks" v-model:form="form" />
          <p v-if="!hasVisibleBlock" class="mb-0 text-xs text-n-ruby-11">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.NONE_VISIBLE') }}
          </p>
        </template>
        <template v-else>
          <FieldChips @insert="insertField" />
          <LetterheadSettings
            v-model:layout="form.layout"
            :template="template"
            @updated="onImageUpdated"
          />
        </template>
      </div>

      <TemplatePreview
        v-if="showPreview && visible"
        :template-id="template.id"
        :payload="previewPayload"
        class="xl:sticky xl:top-4 h-[75vh]"
        @hide="showPreview = false"
      />
    </div>

    <div
      class="sticky bottom-0 z-20 flex flex-wrap items-center gap-2 pt-3 -mx-4 px-4 pb-1 border-t border-n-weak bg-n-solid-2"
    >
      <Button
        type="submit"
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isDirty || !isValid"
      />
      <Button
        v-if="isDirty"
        type="button"
        size="sm"
        variant="ghost"
        color="slate"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DISCARD')"
        @click="reset"
      />
      <span v-if="isDirty" class="text-xs text-n-amber-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.UNSAVED') }}
      </span>
    </div>
  </form>
</template>
