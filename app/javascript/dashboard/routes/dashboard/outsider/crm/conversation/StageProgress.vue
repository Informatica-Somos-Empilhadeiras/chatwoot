<script setup>
// OUTSIDER: barra de etapas do negócio (etapas abertas + ganho). Quem pode editar clica numa
// etapa para mover o negócio.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  pipeline: { type: Object, default: null },
  stageId: { type: Number, required: true },
  status: { type: String, required: true },
  canMove: { type: Boolean, default: false },
});

const emit = defineEmits(['move']);

const { t } = useI18n();

const steps = computed(() =>
  (props.pipeline?.stages || []).filter(stage => stage.kind !== 'lost')
);

const currentIndex = computed(() => {
  if (props.status === 'won') return steps.value.length - 1;
  return steps.value.findIndex(stage => stage.id === props.stageId);
});

const stepState = index => {
  if (props.status === 'won' || index < currentIndex.value) return 'done';
  if (index === currentIndex.value) return 'current';
  return 'todo';
};

const clickable = stage =>
  props.canMove && props.status === 'open' && stage.id !== props.stageId;
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      class="grid gap-1.5"
      :style="{
        gridTemplateColumns: `repeat(${steps.length}, minmax(0, 1fr))`,
      }"
    >
      <button
        v-for="(stage, index) in steps"
        :key="stage.id"
        type="button"
        class="flex flex-col gap-1.5 text-start group disabled:cursor-default"
        :disabled="!clickable(stage)"
        :title="
          clickable(stage)
            ? t('OUTSIDER_CRM.CONVERSATION.MOVE_TO', { stage: stage.name })
            : stage.name
        "
        @click="emit('move', stage)"
      >
        <span
          class="h-2 rounded-full transition-colors"
          :class="{
            'bg-n-teal-9': stepState(index) === 'done',
            'bg-n-blue-10': stepState(index) === 'current',
            'bg-n-alpha-3 group-enabled:group-hover:bg-n-blue-5':
              stepState(index) === 'todo',
          }"
        />
        <span
          class="flex items-center gap-1 text-xs truncate"
          :class="
            stepState(index) === 'current'
              ? 'font-medium text-n-blue-11'
              : 'text-n-slate-11'
          "
        >
          <Icon
            v-if="stepState(index) === 'done'"
            icon="i-lucide-check"
            class="size-3 shrink-0 text-n-teal-11"
          />
          <span class="truncate">{{ stage.name }}</span>
        </span>
      </button>
    </div>
  </div>
</template>
