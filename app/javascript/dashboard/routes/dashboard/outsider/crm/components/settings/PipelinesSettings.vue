<script setup>
// OUTSIDER: pipelines por unidade. Gestores só veem e alteram os das suas unidades.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsSection from './SettingsSection.vue';
import PipelineDialog from './PipelineDialog.vue';
import { errorMessage } from '../../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const dialogRef = ref(null);

const manageableUnits = computed(() =>
  props.units.filter(
    unit =>
      props.access.administrator ||
      props.access.units.some(
        item => item.id === unit.id && item.role === 'manager'
      )
  )
);

const unitOptions = computed(() =>
  manageableUnits.value.map(unit => ({ value: unit.id, label: unit.name }))
);

const groups = computed(() =>
  manageableUnits.value.map(unit => ({
    unit,
    pipelines: props.pipelines.filter(p => p.business_unit_id === unit.id),
  }))
);

const toggleActive = async pipeline => {
  try {
    await CrmAPI.updatePipeline(pipeline.id, { active: !pipeline.active });
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.PIPELINES.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.PIPELINES.DESCRIPTION')"
  >
    <p
      v-if="!manageableUnits.length"
      class="p-6 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('OUTSIDER_CRM.SETTINGS.PIPELINES.NO_UNITS') }}
    </p>

    <div
      v-for="group in groups"
      :key="group.unit.id"
      class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="font-medium text-n-slate-12">{{ group.unit.name }}</span>
        <Button
          icon="i-lucide-plus"
          size="sm"
          variant="outline"
          :label="t('OUTSIDER_CRM.SETTINGS.PIPELINES.NEW')"
          @click="dialogRef.open(null, group.unit.id)"
        />
      </div>
      <p v-if="!group.pipelines.length" class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_CRM.SETTINGS.PIPELINES.EMPTY') }}
      </p>
      <div
        v-for="pipeline in group.pipelines"
        :key="pipeline.id"
        class="flex flex-col gap-2 py-3 border-t border-n-weak"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ pipeline.name }}
          </span>
          <div class="flex items-center gap-3">
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              {{ t('OUTSIDER_CRM.SETTINGS.ACTIVE') }}
              <Switch
                :model-value="pipeline.active"
                @change="toggleActive(pipeline)"
              />
            </label>
            <Button
              icon="i-lucide-pencil"
              size="sm"
              variant="ghost"
              color="slate"
              @click="dialogRef.open(pipeline)"
            />
          </div>
        </div>
        <div class="flex flex-wrap gap-1.5">
          <span
            v-for="stage in pipeline.stages"
            :key="stage.id"
            class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
          >
            <span
              class="rounded-full size-2"
              :style="{ backgroundColor: stage.color || '#64748B' }"
            />
            {{ stage.name }}
            <span class="text-n-slate-10">{{ stage.probability }}%</span>
          </span>
        </div>
      </div>
    </div>

    <PipelineDialog
      ref="dialogRef"
      :unit-options="unitOptions"
      @saved="emit('changed')"
    />
  </SettingsSection>
</template>
