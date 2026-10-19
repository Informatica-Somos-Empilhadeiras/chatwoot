<script setup>
// OUTSIDER: lista de oportunidades com filtros e busca por título ou contato.
// O Kanban chega na próxima entrega; esta lista vira a visualização em tabela.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import OpportunityDialog from './OpportunityDialog.vue';
import {
  STATUS_COLORS,
  errorMessage,
  formatDate,
  formatMoney,
} from '../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
});

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const dialogRef = ref(null);
const isLoading = ref(false);
const opportunities = ref([]);
const meta = ref({ count: 0, page: 1, per_page: 50 });
const filters = ref({
  business_unit_id: '',
  pipeline_id: '',
  status: 'open',
  owner_id: '',
  q: '',
});

const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_UNITS') },
  ...props.units.map(unit => ({ value: unit.id, label: unit.name })),
]);

const pipelineOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_PIPELINES') },
  ...props.pipelines
    .filter(
      pipeline =>
        !filters.value.business_unit_id ||
        pipeline.business_unit_id === filters.value.business_unit_id
    )
    .map(pipeline => ({ value: pipeline.id, label: pipeline.name })),
]);

const statusOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_STATUS') },
  ...['open', 'won', 'lost', 'forwarded'].map(status => ({
    value: status,
    label: t(`OUTSIDER_CRM.STATUS.${status.toUpperCase()}`),
  })),
]);

const ownerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_OWNERS') },
  { value: currentUser.value.id, label: t('OUTSIDER_CRM.FILTERS.MINE') },
]);

const stageNames = computed(() =>
  Object.fromEntries(
    props.pipelines.flatMap(pipeline =>
      pipeline.stages.map(stage => [stage.id, stage])
    )
  )
);

const unitNames = computed(() =>
  Object.fromEntries(props.units.map(unit => [unit.id, unit.name]))
);

const totalValue = computed(() =>
  opportunities.value.reduce((sum, item) => sum + item.value_cents, 0)
);

const pageCount = computed(() =>
  Math.max(1, Math.ceil(meta.value.count / meta.value.per_page))
);

const load = async (page = 1) => {
  isLoading.value = true;
  try {
    const params = Object.fromEntries(
      Object.entries({ ...filters.value, page }).filter(([, v]) => v !== '')
    );
    const { data } = await CrmAPI.getOpportunities(params);
    opportunities.value = data.payload;
    meta.value = data.meta;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const debouncedLoad = useDebounceFn(() => load(1), 300);

watch(
  () => ({ ...filters.value, q: undefined }),
  () => load(1),
  { deep: true }
);
watch(() => filters.value.q, debouncedLoad);
watch(
  () => filters.value.business_unit_id,
  () => {
    filters.value.pipeline_id = '';
  }
);

const openNew = () => dialogRef.value?.open();
const openEdit = opportunity => dialogRef.value?.open(opportunity);

onMounted(() => {
  load(1);
  store.dispatch('agents/get');
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <Input
        v-model="filters.q"
        type="search"
        :placeholder="t('OUTSIDER_CRM.FILTERS.SEARCH')"
        :custom-input-class="['h-8 ltr:!pl-8 rtl:!pr-8 !py-1']"
        class="w-full sm:w-64"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
          />
        </template>
      </Input>
      <Select
        v-if="units.length > 1"
        v-model="filters.business_unit_id"
        :options="unitOptions"
      />
      <Select v-model="filters.pipeline_id" :options="pipelineOptions" />
      <Select v-model="filters.status" :options="statusOptions" />
      <Select v-model="filters.owner_id" :options="ownerOptions" />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <div class="flex-1" />
      <Button
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.OPPORTUNITY.NEW')"
        :disabled="!pipelines.length"
        @click="openNew"
      />
    </div>

    <p
      v-if="!pipelines.length"
      class="p-3 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
    >
      {{ t('OUTSIDER_CRM.STATES.NO_PIPELINES') }}
    </p>

    <div
      class="overflow-x-auto outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <table class="w-full text-sm min-w-[56rem]">
        <thead>
          <tr class="text-xs text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.TABLE.OPPORTUNITY') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.TABLE.CONTACT') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.TABLE.STAGE') }}
            </th>
            <th class="px-4 py-3 font-medium text-right">
              {{ t('OUTSIDER_CRM.TABLE.VALUE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.TABLE.CLOSE_DATE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.TABLE.OWNER') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.TABLE.STATUS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!opportunities.length && !isLoading">
            <td colspan="7" class="px-4 py-10 text-center text-n-slate-11">
              {{ t('OUTSIDER_CRM.STATES.EMPTY') }}
            </td>
          </tr>
          <tr
            v-for="opportunity in opportunities"
            :key="opportunity.id"
            class="border-b cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1"
            @click="openEdit(opportunity)"
          >
            <td class="px-4 py-3">
              <div class="flex flex-col min-w-0">
                <span class="font-medium truncate text-n-slate-12">
                  {{ opportunity.title }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{ opportunity.code }}
                  <template v-if="units.length > 1">
                    · {{ unitNames[opportunity.business_unit_id] }}
                  </template>
                </span>
              </div>
            </td>
            <td class="px-4 py-3">
              <div class="flex items-center min-w-0 gap-2">
                <Avatar
                  :name="opportunity.contact.name"
                  :src="opportunity.contact.thumbnail"
                  :size="24"
                  rounded-full
                />
                <span class="truncate text-n-slate-12">
                  {{ opportunity.contact.name }}
                </span>
              </div>
            </td>
            <td class="px-4 py-3">
              <span class="inline-flex items-center gap-1.5 text-n-slate-12">
                <span
                  class="rounded-full size-2"
                  :style="{
                    backgroundColor:
                      stageNames[opportunity.stage_id]?.color || '#64748B',
                  }"
                />
                {{ stageNames[opportunity.stage_id]?.name }}
              </span>
            </td>
            <td class="px-4 py-3 font-medium text-right text-n-slate-12">
              {{ formatMoney(opportunity.value_cents) }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ formatDate(opportunity.expected_close_on) }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ opportunity.owner?.name }}
            </td>
            <td class="px-4 py-3">
              <span
                class="px-2 py-0.5 text-xs rounded-md"
                :class="STATUS_COLORS[opportunity.status]"
              >
                {{
                  t(`OUTSIDER_CRM.STATUS.${opportunity.status.toUpperCase()}`)
                }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      class="flex flex-wrap items-center justify-between gap-2 text-sm text-n-slate-11"
    >
      <span>
        {{
          t('OUTSIDER_CRM.TABLE.SUMMARY', {
            count: meta.count,
            total: formatMoney(totalValue),
          })
        }}
      </span>
      <div v-if="pageCount > 1" class="flex items-center gap-2">
        <Button
          icon="i-lucide-chevron-left"
          size="xs"
          variant="ghost"
          color="slate"
          :disabled="meta.page <= 1"
          @click="load(meta.page - 1)"
        />
        <span>{{ meta.page }} / {{ pageCount }}</span>
        <Button
          icon="i-lucide-chevron-right"
          size="xs"
          variant="ghost"
          color="slate"
          :disabled="meta.page >= pageCount"
          @click="load(meta.page + 1)"
        />
      </div>
    </div>

    <OpportunityDialog
      ref="dialogRef"
      :access="access"
      :pipelines="pipelines"
      :agents="agents"
      @saved="load(meta.page)"
    />
  </div>
</template>
