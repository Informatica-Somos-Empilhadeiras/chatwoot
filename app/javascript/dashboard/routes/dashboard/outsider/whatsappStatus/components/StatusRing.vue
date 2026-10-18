<script setup>
// OUTSIDER: foto com o anel do WhatsApp, um pedaço por status (cinza quando já visto).
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  name: { type: String, required: true },
  src: { type: String, default: '' },
  // um item por status: true quando já foi visto
  seenFlags: { type: Array, default: () => [] },
});

const RADIUS = 25;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

const segments = computed(() => {
  const count = props.seenFlags.length;
  const slot = CIRCUMFERENCE / count;
  const gap = count > 1 ? 4 : 0;
  return props.seenFlags.map((seen, index) => ({
    dash: `${slot - gap} ${CIRCUMFERENCE - slot + gap}`,
    offset: -index * slot,
    seen,
  }));
});
</script>

<template>
  <div class="relative flex items-center justify-center flex-shrink-0 size-14">
    <svg
      v-if="segments.length"
      class="absolute inset-0 -rotate-90"
      viewBox="0 0 56 56"
    >
      <circle
        v-for="(segment, index) in segments"
        :key="index"
        cx="28"
        cy="28"
        :r="RADIUS"
        fill="none"
        stroke-width="2.5"
        :stroke-dasharray="segment.dash"
        :stroke-dashoffset="segment.offset"
        :class="segment.seen ? 'stroke-n-slate-7' : 'stroke-n-teal-9'"
      />
    </svg>
    <Avatar :name="name" :src="src" :size="44" rounded-full />
  </div>
</template>
