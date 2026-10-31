<script setup>
// OUTSIDER: painel do bloco Enviar documento: manda ao cliente o documento achado pelo Buscar documento,
// como arquivo (WhatsApp da Evolution) ou link com validade.
import { computed, inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TemplateField from './TemplateField.vue';
import { documentVariables } from './integrationTypes';
import { braces } from './template';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const graph = inject('botGraph', ref({ nodes: [] }));
const data = computed(() => props.node.data);

const sources = computed(() => {
  const list = documentVariables(graph.value?.nodes || []);
  return list.includes(data.value.source) || !data.value.source
    ? list
    : [data.value.source, ...list];
});
const clampDays = () => {
  const number = Number(data.value.link_days);
  data.value.link_days = Number.isFinite(number)
    ? Math.min(Math.max(Math.round(number), 1), 30)
    : 7;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.SOURCE') }}
      </span>
      <select v-model="data.source" class="!mb-0 font-mono !text-xs">
        <option v-for="source in sources" :key="source" :value="source">
          {{ braces(source) }}
        </option>
      </select>
      <span v-if="!sources.length" class="text-xs text-n-amber-11">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.NO_SEARCH') }}
      </span>
    </label>
    <div class="grid grid-cols-2 gap-1.5">
      <button
        v-for="mode in ['file', 'link']"
        :key="mode"
        type="button"
        class="flex flex-col items-start gap-0.5 p-2 text-left border rounded-lg"
        :class="
          data.mode === mode
            ? 'border-n-brand bg-n-brand/5'
            : 'border-n-weak hover:bg-n-alpha-1'
        "
        @click="data.mode = mode"
      >
        <span class="text-sm text-n-slate-12">
          {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND_MODES.${mode}`) }}
        </span>
        <span class="text-[11px] leading-snug text-n-slate-10">
          {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.MODE_HINTS.${mode}`) }}
        </span>
      </button>
    </div>
    <TemplateField
      v-if="data.mode === 'file'"
      v-model="data.caption"
      multiline
      :rows="2"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.CAPTION')"
      :placeholder="
        t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.CAPTION_PLACEHOLDER')
      "
      :hint="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.FILE_HINT')"
      :maxlength="1000"
    />
    <template v-else>
      <TemplateField
        v-model="data.link_text"
        multiline
        :rows="3"
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.LINK_TEXT')"
        :placeholder="
          t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.LINK_TEXT_PLACEHOLDER', {
            link: '{{link}}',
          })
        "
        :hint="
          t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.LINK_HINT', {
            link: '{{link}}',
          })
        "
        :maxlength="1000"
      />
      <label
        class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
      >
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.LINK_DAYS') }}
        <input
          v-model.number="data.link_days"
          type="number"
          min="1"
          max="30"
          class="!mb-0 !h-8 !w-20 text-sm"
          @blur="clampDays"
        />
      </label>
    </template>
    <p class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND.PRIVACY_HINT') }}
    </p>
  </div>
</template>
