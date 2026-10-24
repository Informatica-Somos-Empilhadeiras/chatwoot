<script setup>
// OUTSIDER: barra de etapas do negócio (etapas abertas + ganho). Quem pode editar clica numa
// etapa para mover o negócio. compact (Entrega 20, painel do contato e página do contato): só os
// trechos da barra, com o nome da etapa no passar do mouse, e embaixo a etapa atual e "x de y".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  pipeline: { type: Object, default: null },
  stageId: { type: Number, required: true },
  status: { type: String, required: true },
  canMove: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
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

const currentName = computed(() => steps.value[currentIndex.value]?.name || '');

const clickable = stage =>
  props.canMove && props.status === 'open' && stage.id !== props.stageId;
</script>

<template>
  <div v-if="compact" class="flex flex-col gap-1.5">
    <div class="flex gap-1">
      <button
        v-for="(stage, index) in steps"
        :key="stage.id"
        type="button"
        class="flex-1 h-2.5 rounded-full transition-colors disabled:cursor-default"
        :class="{
          'bg-n-teal-9': stepState(index) === 'done',
          'bg-n-blue-10': stepState(index) === 'current',
          'bg-n-slate-5 enabled:hover:bg-n-blue-5': stepState(index) === 'todo',
        }"
        :disabled="!clickable(stage)"
        :title="
          clickable(stage)
            ? t('OUTSIDER_CRM.CONVERSATION.MOVE_TO', { stage: stage.name })
            : stage.name
        "
        :aria-label="stage.name"
        @click="emit('move', stage)"
      />
    </div>
    <span class="flex items-center justify-between gap-2 text-xs">
      <span class="font-medium truncate text-n-blue-11">{{ currentName }}</span>
      <span class="shrink-0 text-n-slate-10">
        {{
          t('OUTSIDER_CRM.CONVERSATION.STAGE_OF', {
            current: currentIndex + 1,
            total: steps.length,
          })
        }}
      </span>
    </span>
  </div>
  <div v-else class="flex flex-col gap-2">
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
            'bg-n-slate-5 group-enabled:group-hover:bg-n-blue-5':
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
