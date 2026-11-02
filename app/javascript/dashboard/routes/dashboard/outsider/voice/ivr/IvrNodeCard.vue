<script setup>
// OUTSIDER: um bloco no fluxograma da URA (Entrega 26), no mesmo formato do bloco do bot: cabeçalho (arrasta o
// bloco), resumo do que a URA faz ali e uma linha por saída, com a bolinha de ligar à direita.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  NODE_TYPES,
  NODE_WIDTH,
  HEADER_HEIGHT,
  BODY_HEIGHT,
  PORT_HEIGHT,
  portsOf,
} from './ivrNodes';

const props = defineProps({
  node: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  connecting: { type: Boolean, default: false },
  warnings: { type: Array, default: () => [] },
  connectedPorts: { type: Array, default: () => [] },
  // pessoas com ramal e filiais (Telefonia > Configurações), para o resumo do Transferir
  options: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['dragStart', 'portDown', 'select']);

const { t } = useI18n();

const meta = computed(() => NODE_TYPES[props.node.type]);
const data = computed(() => props.node.data || {});
const ports = computed(() => portsOf(props.node, t));

const DAY_KEYS = ['0', '1', '2', '3', '4', '5', '6'];

const promptText = value =>
  value?.audio_id
    ? `🎵 ${t('OUTSIDER_VOICE.IVR.SUMMARY.AUDIO')}`
    : value?.text || '';

const transferSummary = d => {
  if (d.target === 'users') {
    const names = (props.options.people || [])
      .filter(person => d.user_ids?.includes(person.id))
      .map(person => person.name);
    return names.join(', ') || '—';
  }
  if (d.target === 'branch') {
    return (
      (props.options.branches || []).find(item => item.id === d.branch_id)
        ?.name || '—'
    );
  }
  if (d.target === 'number') return d.number || '—';
  return t(`OUTSIDER_VOICE.IVR.TARGETS.${d.target}`);
};

const summary = computed(() => {
  const d = data.value;
  switch (props.node.type) {
    case 'start':
      return t('OUTSIDER_VOICE.IVR.SUMMARY.START');
    case 'hours': {
      const open = DAY_KEYS.filter(day => d.hours?.[day]?.enabled);
      if (!open.length) return t('OUTSIDER_VOICE.IVR.SUMMARY.ALWAYS_CLOSED');
      const first = d.hours[open[0]];
      return `${open.map(day => t(`OUTSIDER_TOOLS.BOT.DAYS_SHORT.${day}`)).join(' ')} · ${first.start}–${first.end}`;
    }
    case 'caller':
      return t('OUTSIDER_VOICE.IVR.SUMMARY.CALLER');
    case 'transfer':
      return [`→ ${transferSummary(d)}`, promptText(d.prompt)]
        .filter(Boolean)
        .join('\n');
    case 'collect':
      return (
        promptText(d.prompt) ||
        t('OUTSIDER_VOICE.IVR.SUMMARY.COLLECT', { variable: d.variable })
      );
    default:
      return promptText(d.prompt) || t('OUTSIDER_VOICE.IVR.SUMMARY.EMPTY');
  }
});

const badge = computed(() => {
  const d = data.value;
  if (props.node.type === 'collect') return `{{${d.variable}}}`;
  if (props.node.type === 'menu' && d.label) return d.label;
  if (props.node.type === 'transfer') return `${d.ring_seconds}s`;
  if (props.node.type === 'voicemail') return `${d.max_seconds}s`;
  return '';
});

const style = computed(() => ({
  left: `${props.node.x}px`,
  top: `${props.node.y}px`,
  width: `${NODE_WIDTH}px`,
}));
</script>

<template>
  <div
    class="absolute transition-shadow border shadow-sm select-none rounded-xl bg-n-solid-1"
    :class="[
      selected
        ? 'border-n-brand ring-2 ring-n-brand/30 shadow-lg z-20'
        : 'border-n-weak hover:shadow-md z-10',
      connecting && node.type !== 'start'
        ? 'outline-dashed outline-2 outline-n-brand/40'
        : '',
    ]"
    :style="style"
    :data-node-id="node.id"
    data-testid="ivr-node"
    @pointerdown.stop="emit('select', node.id)"
  >
    <span
      v-if="node.type !== 'start'"
      class="absolute -left-[7px] size-3.5 rounded-full border-2 border-n-solid-1 bg-n-slate-9"
      :style="{ top: `${HEADER_HEIGHT / 2 - 7}px` }"
    />
    <div
      class="flex items-center gap-2 px-3 cursor-grab active:cursor-grabbing rounded-t-xl"
      :style="{ height: `${HEADER_HEIGHT}px` }"
      @pointerdown.stop="emit('dragStart', $event)"
    >
      <span
        class="flex items-center justify-center text-white rounded-md size-6 shrink-0"
        :class="meta.color"
      >
        <Icon :icon="meta.icon" class="size-3.5" />
      </span>
      <span class="text-sm font-semibold truncate text-n-slate-12">
        {{ t(`OUTSIDER_VOICE.IVR.TYPES.${node.type}`) }}
      </span>
      <span
        v-if="badge"
        class="px-1.5 py-0.5 ml-auto text-[10px] font-medium rounded-md shrink-0 truncate max-w-[6rem]"
        :class="meta.soft"
      >
        {{ badge }}
      </span>
      <Icon
        v-if="warnings.length"
        v-tooltip.top="warnings.join('\n')"
        icon="i-lucide-triangle-alert"
        class="size-4 shrink-0 text-n-amber-10"
        :class="{ 'ml-auto': !badge }"
      />
    </div>
    <div
      class="px-3 pt-1.5 overflow-hidden text-xs leading-[18px] whitespace-pre-line break-words text-n-slate-11 border-t border-n-weak"
      :style="{ height: `${BODY_HEIGHT}px` }"
    >
      <span class="line-clamp-3">{{ summary }}</span>
    </div>
    <div class="pb-2">
      <div
        v-for="port in ports"
        :key="port.id"
        class="relative flex items-center justify-end pr-4 text-xs border-t border-n-weak/60"
        :class="port.muted ? 'text-n-slate-10 italic' : 'text-n-slate-12'"
        :style="{ height: `${PORT_HEIGHT}px` }"
      >
        <span class="truncate">{{ port.label }}</span>
        <span
          class="absolute -right-[8px] size-4 rounded-full border-2 border-n-solid-1 cursor-crosshair hover:scale-125 transition-transform"
          :class="
            connectedPorts.includes(port.id) ? meta.color : 'bg-n-slate-6'
          "
          :data-port-id="port.id"
          @pointerdown.stop.prevent="emit('portDown', port.id, $event)"
        />
      </div>
    </div>
  </div>
</template>
