<script setup>
// OUTSIDER: ligação da proposta com um negócio. É opcional: o negócio nunca depende de proposta.
// Dá para escolher um negócio do contato (que a pessoa vê) ou criar um com esta proposta, na
// unidade e no pipeline escolhidos, com o valor igual ao total.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/outsider/crm';
import Select from 'dashboard/components-next/select/Select.vue';
import { CRM_ROUTE } from '../../sections';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
  // negócio já ligado (vem da proposta salva)
  current: { type: Object, default: null },
  readOnly: { type: Boolean, default: false },
});

// { mode: 'none' | 'existing' | 'create', opportunity_id, business_unit_id, pipeline_id }
const link = defineModel({ type: Object, required: true });

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const opportunities = ref([]);

const modeOptions = computed(() =>
  ['none', 'existing', 'create'].map(mode => ({
    value: mode,
    label: t(`OUTSIDER_CRM.PROPOSALS.DEAL.MODES.${mode.toUpperCase()}`),
  }))
);

const opportunityOptions = computed(() => {
  const list = [...opportunities.value];
  if (props.current && !list.some(item => item.id === props.current.id)) {
    list.unshift(props.current);
  }
  return list.map(item => ({
    value: item.id,
    label: `${item.code} · ${item.title}${
      item.status === 'open'
        ? ''
        : ` (${t(`OUTSIDER_CRM.STATUS.${item.status.toUpperCase()}`)})`
    }`,
  }));
});

const unitOptions = computed(() =>
  props.units.map(unit => ({ value: unit.id, label: unit.name }))
);

const pipelineOptions = computed(() =>
  props.pipelines
    .filter(
      pipeline =>
        pipeline.active &&
        pipeline.business_unit_id === link.value.business_unit_id
    )
    .map(pipeline => ({ value: pipeline.id, label: pipeline.name }))
);

const load = async () => {
  opportunities.value = [];
  if (!props.contactId) return;
  try {
    const { data } = await CrmAPI.getOpportunities({
      contact_id: props.contactId,
    });
    opportunities.value = data.payload;
  } catch {
    // sem a lista, ainda dá para criar o negócio ou deixar sem
    opportunities.value = [];
  }
};

watch(() => props.contactId, load, { immediate: true });

// unidade escolhida: o primeiro pipeline ativo dela
watch(
  () => link.value.business_unit_id,
  () => {
    if (
      !pipelineOptions.value.some(
        option => option.value === link.value.pipeline_id
      )
    ) {
      link.value.pipeline_id = pipelineOptions.value[0]?.value || '';
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center gap-2">
      <Select
        v-model="link.mode"
        :options="modeOptions"
        :disabled="readOnly || !contactId"
      />
      <Select
        v-if="link.mode === 'existing'"
        v-model="link.opportunity_id"
        :options="opportunityOptions"
        :placeholder="t('OUTSIDER_CRM.PROPOSALS.DEAL.CHOOSE')"
        :disabled="readOnly"
        class="min-w-[16rem] [&>select]:w-full"
      />
      <template v-if="link.mode === 'create'">
        <Select
          v-model="link.business_unit_id"
          :options="unitOptions"
          :placeholder="t('OUTSIDER_CRM.PROPOSALS.DEAL.UNIT')"
          :disabled="readOnly"
        />
        <Select
          v-model="link.pipeline_id"
          :options="pipelineOptions"
          :placeholder="t('OUTSIDER_CRM.PROPOSALS.DEAL.PIPELINE')"
          :disabled="readOnly"
        />
      </template>
      <router-link
        v-if="current && link.mode === 'existing'"
        :to="
          accountScopedRoute(
            CRM_ROUTE,
            { tab: 'opportunities' },
            { negocio: current.id }
          )
        "
        class="text-sm text-n-blue-11 hover:underline"
      >
        {{ t('OUTSIDER_CRM.PROPOSALS.DEAL.OPEN', { code: current.code }) }}
      </router-link>
    </div>
    <p
      v-if="link.mode === 'existing' && !opportunityOptions.length"
      class="mb-0 text-xs text-n-slate-11"
    >
      {{ t('OUTSIDER_CRM.PROPOSALS.DEAL.NONE_FOR_CONTACT') }}
    </p>
    <p v-if="link.mode === 'create'" class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSALS.DEAL.CREATE_HELP') }}
    </p>
  </div>
</template>
