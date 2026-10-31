<script setup>
// OUTSIDER: escolha da conexão (ou da planilha) num bloco do bot, com recarregar e o atalho para a aba de
// cadastro, que abre em outra guia para não perder o fluxo aberto.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { useIntegrations, loadIntegrations } from './useIntegrations';

const props = defineProps({
  modelValue: { type: [Number, String], default: null },
  // http | nextcloud | postgres | dataset
  kind: { type: String, required: true },
  label: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const router = useRouter();
const store = useIntegrations();

const isDataset = computed(() => props.kind === 'dataset');
const options = computed(() =>
  isDataset.value
    ? store.datasets.map(item => ({
        id: item.id,
        name: t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.DATASET_OPTION', {
          name: item.name,
          count: item.rows_count,
        }),
      }))
    : store.connections
        .filter(item => item.kind === props.kind)
        .map(item => ({
          id: item.id,
          name: item.allow_write
            ? item.name
            : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.READ_ONLY_OPTION', {
                name: item.name,
              }),
        }))
);
const missing = computed(
  () =>
    store.loaded &&
    props.modelValue &&
    !options.value.some(item => item.id === Number(props.modelValue))
);

const manage = () => {
  const { href } = router.resolve({
    name: 'outsider_bot_flows',
    query: { tab: isDataset.value ? 'datasets' : 'connections' },
  });
  window.open(href, '_blank', 'noopener');
};

const select = value => emit('update:modelValue', value ? Number(value) : null);
</script>

<template>
  <div class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-12">
      {{
        label ||
        t(
          isDataset
            ? 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.DATASET'
            : 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.CONNECTION'
        )
      }}
    </span>
    <div class="flex items-center gap-1">
      <select
        :value="modelValue || ''"
        class="flex-1 min-w-0 !mb-0"
        @change="select($event.target.value)"
      >
        <option value="">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.CHOOSE') }}
        </option>
        <option v-for="item in options" :key="item.id" :value="item.id">
          {{ item.name }}
        </option>
      </select>
      <Button
        v-tooltip.top="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.RELOAD')"
        icon="i-lucide-refresh-cw"
        xs
        ghost
        slate
        :is-loading="store.loading"
        @click="loadIntegrations(true)"
      />
      <Button
        v-tooltip.top="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.MANAGE')"
        icon="i-lucide-external-link"
        xs
        ghost
        slate
        @click="manage"
      />
    </div>
    <span v-if="missing" class="text-xs text-n-ruby-11">
      {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.GONE') }}
    </span>
    <button
      v-else-if="store.loaded && !options.length"
      type="button"
      class="text-xs text-left text-n-brand hover:underline"
      @click="manage"
    >
      {{
        t(
          isDataset
            ? 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.NO_DATASETS'
            : `OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.NO_CONNECTIONS_${kind.toUpperCase()}`
        )
      }}
    </button>
  </div>
</template>
