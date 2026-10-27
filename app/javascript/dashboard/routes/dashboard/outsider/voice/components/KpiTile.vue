<script setup>
// OUTSIDER: um número do painel da Telefonia (Entrega 24): o valor grande, a explicação embaixo e a
// diferença com o período anterior. better diz qual lado é bom (up, down ou none): menos perdidas é bom,
// tempo de conversa não é bom nem ruim.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  hint: { type: String, default: '' },
  icon: { type: String, default: '' },
  current: { type: Number, default: null },
  previous: { type: Number, default: null },
  // taxa (%): a diferença vai em pontos
  points: { type: Boolean, default: false },
  better: { type: String, default: 'up' },
});

const { t } = useI18n();

const delta = computed(() => {
  if (props.current === null || props.previous === null) return null;
  const diff = props.current - props.previous;
  if (props.points) {
    return {
      diff,
      text: t('OUTSIDER_VOICE.WALLBOARD.DELTA.POINTS', {
        value: `${diff > 0 ? '+' : ''}${diff.toFixed(1).replace('.', ',')}`,
      }),
    };
  }
  if (!props.previous) {
    return props.current
      ? { diff, text: t('OUTSIDER_VOICE.WALLBOARD.DELTA.NEW') }
      : null;
  }
  const percent = Math.round((diff * 100) / props.previous);
  return {
    diff,
    text: t('OUTSIDER_VOICE.WALLBOARD.DELTA.PERCENT', {
      value: `${percent > 0 ? '+' : ''}${percent}`,
    }),
  };
});

const tone = computed(() => {
  if (!delta.value || !delta.value.diff || props.better === 'none') {
    return 'text-n-slate-11';
  }
  const good =
    props.better === 'up' ? delta.value.diff > 0 : delta.value.diff < 0;
  return good ? 'text-n-teal-11' : 'text-n-ruby-11';
});
</script>

<template>
  <div
    class="flex flex-col gap-1 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
  >
    <span class="flex items-start gap-1.5 text-xs text-n-slate-11">
      <Icon v-if="icon" :icon="icon" class="size-3.5 shrink-0 mt-px" />
      <span class="line-clamp-2">{{ label }}</span>
    </span>
    <span class="text-2xl font-medium tabular-nums text-n-slate-12">
      {{ value }}
    </span>
    <span v-if="hint" class="text-xs text-n-slate-11">{{ hint }}</span>
    <span
      v-if="delta"
      class="flex items-center gap-1 text-xs tabular-nums"
      :class="tone"
    >
      <Icon
        :icon="
          delta.diff > 0
            ? 'i-lucide-trending-up'
            : delta.diff < 0
              ? 'i-lucide-trending-down'
              : 'i-lucide-minus'
        "
        class="size-3.5 shrink-0"
      />
      {{ delta.text }}
    </span>
  </div>
</template>
