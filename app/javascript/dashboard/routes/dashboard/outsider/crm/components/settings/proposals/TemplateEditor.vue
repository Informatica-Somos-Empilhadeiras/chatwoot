<script setup>
// OUTSIDER: edição de um modelo de proposta: nome, ativo, papel timbrado, validade, estilo e lista das
// condições, textos e o que aparece no PDF. Salvar manda só as chaves do conteúdo que mudaram (o
// servidor junta com o que já existe).
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
import TemplateImageSlot from './TemplateImageSlot.vue';
import ConditionsEditor from './ConditionsEditor.vue';
import FieldChips from './FieldChips.vue';
import {
  FLAG_KEYS,
  MAX_TEXT,
  TEXT_FIELDS,
  TEXT_KEYS,
  conditionRow,
  settingsError,
} from './proposalSettings';

const props = defineProps({
  template: { type: Object, required: true },
});

const emit = defineEmits(['updated', 'dirty']);

const { t } = useI18n();

const CONTENT_KEYS = [
  ...TEXT_KEYS,
  ...FLAG_KEYS,
  'validity_days',
  'conditions_style',
  'conditions',
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
  };
};

const name = ref('');
const active = ref(true);
const form = ref({});
const isSaving = ref(false);

const reset = () => {
  name.value = props.template.name;
  active.value = props.template.active;
  form.value = contentOf(props.template);
};
reset();

const original = computed(() => contentOf(props.template));

// condições sem o uid, para comparar e enviar
const plain = (key, value) =>
  key === 'conditions'
    ? value.map(row => ({ label: row.label, text: row.text }))
    : value;

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
const isValid = computed(() => !!name.value.trim() && validityValid.value);

const styleOptions = computed(() =>
  ['table', 'list'].map(style => ({
    value: style,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.STYLES.${style.toUpperCase()}`
    ),
  }))
);

const textLabel = key =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.TEXTS.${key.toUpperCase()}`);
const textHelp = key =>
  t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.TEXTS_HELP.${key.toUpperCase()}`);

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

const save = async () => {
  if (!isValid.value || !isDirty.value) return;
  const payload = { name: name.value.trim(), active: active.value };
  if (changedKeys.value.length) {
    payload.content = Object.fromEntries(
      changedKeys.value.map(key => [
        key,
        key === 'validity_days'
          ? Number(form.value[key])
          : plain(key, form.value[key]),
      ])
    );
  }
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalTemplate(
      props.template.id,
      payload
    );
    emit('updated', data);
    // a resposta já vem normalizada (linhas vazias de condição saem)
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

const textareaClass =
  '!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand placeholder:text-n-slate-10';
</script>

<template>
  <form
    class="flex flex-col gap-6 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
    @submit.prevent="save"
    @focusin="onFocusIn"
  >
    <!-- Nome e ativo -->
    <div class="flex flex-wrap items-end gap-4">
      <Input
        v-model="name"
        maxlength="255"
        class="flex-1 min-w-[14rem]"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.NAME')"
        :message-type="name.trim() ? 'info' : 'error'"
      />
      <label class="flex items-center gap-2 h-10 text-sm text-n-slate-12">
        <Switch v-model="active" />
        {{ t('OUTSIDER_CRM.SETTINGS.ACTIVE') }}
      </label>
      <Label
        :label="
          t(
            `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.KINDS.${template.kind.toUpperCase()}`
          )
        "
        class="mb-2.5"
        compact
      />
    </div>
    <p v-if="!active" class="mb-0 -mt-4 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.INACTIVE_HELP') }}
    </p>

    <!-- Papel timbrado -->
    <section class="flex flex-col gap-3">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.LETTERHEAD') }}
      </h4>
      <div class="grid gap-4 sm:grid-cols-2">
        <TemplateImageSlot
          :template="template"
          position="header"
          @updated="data => emit('updated', data)"
        />
        <TemplateImageSlot
          :template="template"
          position="footer"
          @updated="data => emit('updated', data)"
        />
      </div>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.LETTERHEAD_HELP') }}
      </p>
    </section>

    <!-- O que aparece -->
    <section class="flex flex-col gap-3">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.SHOW') }}
      </h4>
      <div class="grid gap-2 sm:grid-cols-2">
        <label
          v-for="flag in FLAG_KEYS"
          :key="flag"
          class="flex items-start gap-3 p-3 rounded-lg bg-n-alpha-1"
        >
          <Switch v-model="form[flag]" class="mt-0.5" />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm text-n-slate-12">
              {{
                t(
                  `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FLAGS.${flag.toUpperCase()}`
                )
              }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                t(
                  `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FLAGS_HELP.${flag.toUpperCase()}`
                )
              }}
            </span>
          </span>
        </label>
      </div>
      <div class="flex flex-wrap items-start gap-4">
        <div class="flex flex-col gap-1">
          <Input
            v-model="form.validity_days"
            type="number"
            min="0"
            max="365"
            class="w-40"
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY')"
            :message-type="validityValid ? 'info' : 'error'"
          />
          <span class="text-xs text-n-slate-11 max-w-[16rem]">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY_HELP') }}
          </span>
        </div>
        <label class="flex flex-col gap-1 text-sm">
          <span class="mb-0.5 font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.STYLE') }}
          </span>
          <Select v-model="form.conditions_style" :options="styleOptions" />
          <span class="text-xs text-n-slate-11 max-w-[20rem]">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.STYLE_HELP') }}
          </span>
        </label>
      </div>
    </section>

    <!-- Textos -->
    <section class="flex flex-col gap-3">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.TEXTS_TITLE') }}
      </h4>
      <FieldChips @insert="insertField" />
      <div class="grid gap-4 sm:grid-cols-2">
        <label
          v-for="field in TEXT_FIELDS"
          :key="field.key"
          data-fields
          class="flex flex-col gap-1 text-sm"
          :class="{ 'sm:col-span-2': field.multiline }"
        >
          <span class="font-medium text-n-slate-12">
            {{ textLabel(field.key) }}
          </span>
          <textarea
            v-if="field.multiline"
            v-model="form[field.key]"
            rows="3"
            :maxlength="MAX_TEXT"
            :class="textareaClass"
          />
          <input
            v-else
            v-model="form[field.key]"
            type="text"
            :maxlength="MAX_TEXT"
            :class="textareaClass"
          />
          <span class="text-xs text-n-slate-11">
            {{ textHelp(field.key) }}
          </span>
        </label>
      </div>
    </section>

    <!-- Condições -->
    <section class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.TITLE') }}
        </h4>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.HELP') }}
        </p>
      </div>
      <ConditionsEditor v-model="form.conditions" />
    </section>

    <div
      class="sticky bottom-0 flex flex-wrap items-center gap-2 pt-3 -mx-4 px-4 pb-1 border-t border-n-weak bg-n-solid-2"
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
