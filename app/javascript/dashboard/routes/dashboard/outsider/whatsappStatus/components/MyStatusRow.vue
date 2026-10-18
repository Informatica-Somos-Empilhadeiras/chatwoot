<script setup>
// OUTSIDER: um dos meus status na visão em lista.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import StatusThumbnail from './StatusThumbnail.vue';
import StatusCounts from './StatusCounts.vue';
import StatusActions from './StatusActions.vue';
import { situation, timeLabel, typeLabel } from '../helpers';

const props = defineProps({
  status: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  can: { type: Object, default: () => ({}) },
  selectable: { type: Boolean, default: false },
  downloading: { type: Boolean, default: false },
});

const emit = defineEmits([
  'toggle',
  'view',
  'interactions',
  'republish',
  'download',
]);

const { t } = useI18n();

const badge = computed(() => situation(t, props.status));
</script>

<template>
  <div
    class="flex items-center gap-4 px-4 py-3"
    :class="selected ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
  >
    <Checkbox
      v-if="selectable"
      :model-value="selected"
      @update:model-value="emit('toggle')"
    />
    <button
      type="button"
      class="flex-shrink-0 p-0 overflow-hidden rounded-lg size-12 disabled:cursor-default"
      :disabled="status.deleted"
      @click="emit('view')"
    >
      <StatusThumbnail :status="status" class="size-full" />
    </button>
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <span
        class="text-sm truncate"
        :class="status.text ? 'text-n-slate-12' : 'text-n-slate-10'"
      >
        {{ status.text || t('OUTSIDER_WHATSAPP_STATUS.MINE.NO_TEXT') }}
      </span>
      <span class="text-xs truncate text-n-slate-11">
        {{ typeLabel(t, status.type) }} · {{ timeLabel(t, status.timestamp) }}
      </span>
    </div>
    <Label
      :label="badge.label"
      :color="badge.color"
      compact
      class="hidden sm:inline-flex"
    />
    <StatusCounts :status="status" @click="emit('interactions')" />
    <StatusActions
      :status="status"
      :can="can"
      :downloading="downloading"
      @view="emit('view')"
      @republish="emit('republish')"
      @download="emit('download')"
    />
  </div>
</template>
