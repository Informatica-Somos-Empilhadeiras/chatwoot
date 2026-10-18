<script setup>
// OUTSIDER: um dos meus status na visão em cards.
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
  inboxId: { type: Number, required: true },
});

const emit = defineEmits([
  'toggle',
  'view',
  'interactions',
  'edit',
  'republish',
  'download',
]);

const { t } = useI18n();

const badge = computed(() => situation(t, props.status));
// o texto do status de texto já aparece na miniatura
const caption = computed(() =>
  props.status.type === 'text' ? '' : props.status.text
);
</script>

<template>
  <div
    class="relative flex flex-col overflow-hidden outline outline-1 -outline-offset-1 rounded-xl bg-n-solid-2"
    :class="selected ? 'outline-n-brand' : 'outline-n-container'"
  >
    <button
      type="button"
      class="relative block w-full p-0 overflow-hidden rounded-none aspect-[4/5] disabled:cursor-default"
      :disabled="status.deleted"
      @click="emit('view')"
    >
      <div class="absolute inset-0">
        <StatusThumbnail
          :status="status"
          :inbox-id="inboxId"
          large
          class="size-full"
        />
      </div>
    </button>
    <div
      v-if="selectable"
      class="absolute flex items-center justify-center rounded-md shadow top-2 ltr:left-2 rtl:right-2 size-7 bg-n-solid-2"
    >
      <Checkbox :model-value="selected" @update:model-value="emit('toggle')" />
    </div>
    <Label
      :label="badge.label"
      :color="badge.color"
      compact
      class="absolute shadow top-2 ltr:right-2 rtl:left-2"
    />
    <div class="flex flex-col gap-1 p-3">
      <p
        class="mb-0 text-sm truncate"
        :class="caption ? 'text-n-slate-12' : 'text-n-slate-10'"
      >
        {{ caption || typeLabel(t, status.type) }}
      </p>
      <span class="text-xs text-n-slate-11">
        {{ timeLabel(t, status.timestamp) }}
      </span>
      <div class="flex items-center justify-between gap-1 -mx-2">
        <StatusCounts :status="status" @click="emit('interactions')" />
        <StatusActions
          :status="status"
          :can="can"
          :downloading="downloading"
          @view="emit('view')"
          @edit="emit('edit')"
          @republish="emit('republish')"
          @download="emit('download')"
        />
      </div>
    </div>
  </div>
</template>
