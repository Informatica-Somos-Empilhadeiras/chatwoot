<script setup>
// OUTSIDER: criar e editar pipeline com suas etapas. Precisa de ao menos uma etapa aberta;
// etapas de ganho e perda fecham a oportunidade. Etapa com oportunidades não pode ser removida.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { STAGE_COLORS, errorMessage } from '../../helpers';

const props = defineProps({
  unitOptions: { type: Array, required: true },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();

const dialogRef = ref(null);
const isSaving = ref(false);
const pipelineId = ref(null);
const form = ref({ name: '', business_unit_id: '' });
const stages = ref([]);
const removed = ref([]);

const defaultStages = () => [
  {
    name: t('OUTSIDER_CRM.SETTINGS.PIPELINES.DEFAULT_STAGES.LEAD'),
    probability: 10,
    kind: 'open',
    color: STAGE_COLORS[0],
  },
  {
    name: t('OUTSIDER_CRM.SETTINGS.PIPELINES.DEFAULT_STAGES.QUALIFIED'),
    probability: 30,
    kind: 'open',
    color: STAGE_COLORS[1],
  },
  {
    name: t('OUTSIDER_CRM.SETTINGS.PIPELINES.DEFAULT_STAGES.PROPOSAL'),
    probability: 55,
    kind: 'open',
    color: STAGE_COLORS[2],
  },
  {
    name: t('OUTSIDER_CRM.SETTINGS.PIPELINES.DEFAULT_STAGES.NEGOTIATION'),
    probability: 80,
    kind: 'open',
    color: STAGE_COLORS[3],
  },
  {
    name: t('OUTSIDER_CRM.SETTINGS.PIPELINES.DEFAULT_STAGES.WON'),
    probability: 100,
    kind: 'won',
    color: '#10B981',
  },
  {
    name: t('OUTSIDER_CRM.SETTINGS.PIPELINES.DEFAULT_STAGES.LOST'),
    probability: 0,
    kind: 'lost',
    color: '#EF4444',
  },
];

const kindOptions = computed(() =>
  ['open', 'won', 'lost'].map(kind => ({
    value: kind,
    label: t(`OUTSIDER_CRM.SETTINGS.PIPELINES.KINDS.${kind.toUpperCase()}`),
  }))
);

const isValid = computed(
  () =>
    form.value.name.trim() &&
    form.value.business_unit_id &&
    stages.value.every(stage => stage.name.trim()) &&
    stages.value.some(stage => stage.kind === 'open')
);

const open = (pipeline = null, unitId = '') => {
  pipelineId.value = pipeline?.id ?? null;
  removed.value = [];
  form.value = {
    name: pipeline?.name ?? '',
    business_unit_id:
      pipeline?.business_unit_id ?? unitId ?? props.unitOptions[0]?.value,
  };
  stages.value = pipeline
    ? pipeline.stages.map(stage => ({ ...stage }))
    : defaultStages();
  dialogRef.value?.open();
};

const addStage = () => {
  const openCount = stages.value.filter(s => s.kind === 'open').length;
  stages.value.splice(openCount, 0, {
    name: '',
    probability: 50,
    kind: 'open',
    color: STAGE_COLORS[openCount % STAGE_COLORS.length],
  });
};

const move = (index, step) => {
  const target = index + step;
  if (target < 0 || target >= stages.value.length) return;
  const list = [...stages.value];
  [list[index], list[target]] = [list[target], list[index]];
  stages.value = list;
};

const remove = index => {
  const [stage] = stages.value.splice(index, 1);
  if (stage.id) removed.value.push(stage.id);
};

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  const stagesAttributes = [
    ...stages.value.map((stage, index) => ({
      id: stage.id,
      name: stage.name.trim(),
      probability: Number(stage.probability) || 0,
      kind: stage.kind,
      color: stage.color,
      position: index + 1,
    })),
    ...removed.value.map(id => ({ id, _destroy: true })),
  ];
  try {
    const payload = { ...form.value, stages_attributes: stagesAttributes };
    if (pipelineId.value) {
      await CrmAPI.updatePipeline(pipelineId.value, payload);
    } else {
      await CrmAPI.createPipeline(payload);
    }
    dialogRef.value?.close();
    emit('saved');
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      pipelineId
        ? t('OUTSIDER_CRM.SETTINGS.PIPELINES.EDIT')
        : t('OUTSIDER_CRM.SETTINGS.PIPELINES.NEW')
    "
    width="2xl"
    overflow-y-auto
    :confirm-button-label="t('OUTSIDER_CRM.SAVE')"
    :is-loading="isSaving"
    :disable-confirm-button="!isValid"
    @confirm="save"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="form.name"
          :label="t('OUTSIDER_CRM.SETTINGS.PIPELINES.NAME')"
          :placeholder="t('OUTSIDER_CRM.SETTINGS.PIPELINES.NAME_PLACEHOLDER')"
        />
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.OPPORTUNITY.UNIT') }}
          </span>
          <Select
            v-model="form.business_unit_id"
            :options="unitOptions"
            :disabled="!!pipelineId"
            class="!w-full [&>select]:w-full"
          />
        </label>
      </div>

      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.PIPELINES.STAGES') }}
          </span>
          <Button
            type="button"
            icon="i-lucide-plus"
            size="xs"
            variant="ghost"
            :label="t('OUTSIDER_CRM.SETTINGS.PIPELINES.ADD_STAGE')"
            @click="addStage"
          />
        </div>
        <div
          v-for="(stage, index) in stages"
          :key="stage.id || `new-${index}`"
          class="flex flex-wrap items-center gap-2 p-2 rounded-lg bg-n-alpha-1"
        >
          <input
            v-model="stage.color"
            type="color"
            class="p-0 bg-transparent border-0 rounded cursor-pointer size-7"
          />
          <Input
            v-model="stage.name"
            class="flex-1 min-w-[10rem]"
            :placeholder="t('OUTSIDER_CRM.SETTINGS.PIPELINES.STAGE_NAME')"
          />
          <Input
            v-model="stage.probability"
            type="number"
            min="0"
            max="100"
            class="w-20"
            placeholder="%"
          />
          <Select v-model="stage.kind" :options="kindOptions" />
          <Button
            type="button"
            icon="i-lucide-arrow-up"
            size="xs"
            variant="ghost"
            color="slate"
            :disabled="index === 0"
            @click="move(index, -1)"
          />
          <Button
            type="button"
            icon="i-lucide-arrow-down"
            size="xs"
            variant="ghost"
            color="slate"
            :disabled="index === stages.length - 1"
            @click="move(index, 1)"
          />
          <Button
            type="button"
            icon="i-lucide-trash-2"
            size="xs"
            variant="ghost"
            color="ruby"
            @click="remove(index)"
          />
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.SETTINGS.PIPELINES.STAGES_HELP') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
