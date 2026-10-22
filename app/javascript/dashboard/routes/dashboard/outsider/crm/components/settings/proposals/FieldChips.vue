<script setup>
// OUTSIDER: ajuda dos textos do modelo: **negrito** e os campos automáticos que o PDF preenche
// ({cliente.empresa}, {proposta.validade}...). Clicar num campo insere no texto em edição.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { PROPOSAL_FIELDS } from './proposalSettings';

const emit = defineEmits(['insert']);

const { t } = useI18n();
const isOpen = ref(false);

const token = (group, key) => `{${group}.${key}}`;

const fieldLabel = (group, key) =>
  t(
    `OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.${group.toUpperCase()}.${key.toUpperCase()}`
  );
</script>

<template>
  <div class="flex flex-col gap-2 p-3 text-xs rounded-xl bg-n-alpha-1">
    <div class="flex items-start gap-2 text-n-slate-11">
      <Icon icon="i-lucide-info" class="size-4 shrink-0 text-n-slate-10" />
      <span class="flex-1">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.HELP') }}
      </span>
      <button
        type="button"
        class="font-medium shrink-0 text-n-blue-11 hover:underline"
        @click="isOpen = !isOpen"
      >
        {{
          isOpen
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.HIDE')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.SHOW')
        }}
      </button>
    </div>
    <div v-if="isOpen" class="flex flex-col gap-2">
      <div
        v-for="item in PROPOSAL_FIELDS"
        :key="item.group"
        class="flex flex-wrap items-center gap-1.5"
      >
        <span class="w-20 font-medium text-n-slate-11 shrink-0">
          {{
            t(
              `OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.GROUPS.${item.group.toUpperCase()}`
            )
          }}
        </span>
        <button
          v-for="key in item.keys"
          :key="key"
          v-tooltip.top="fieldLabel(item.group, key)"
          type="button"
          class="px-1.5 py-0.5 font-mono rounded-md bg-n-solid-3 text-n-slate-12 hover:bg-n-alpha-2 outline outline-1 -outline-offset-1 outline-n-weak"
          @mousedown.prevent
          @click="emit('insert', token(item.group, key))"
        >
          {{ token(item.group, key) }}
        </button>
      </div>
      <p class="mb-0 text-n-slate-10">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.CLICK') }}
      </p>
    </div>
  </div>
</template>
