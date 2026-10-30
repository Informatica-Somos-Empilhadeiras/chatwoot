<script setup>
// OUTSIDER: um bloco no fluxograma do bot. Medidas fixas (nodeTypes.js) para as setas ficarem no
// lugar: cabeçalho (arrasta o bloco), resumo e uma linha por saída, com a bolinha de ligar à direita.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  NODE_TYPES,
  NODE_WIDTH,
  HEADER_HEIGHT,
  BODY_HEIGHT,
  PORT_HEIGHT,
  portsOf,
} from './nodeTypes';

const props = defineProps({
  node: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  connecting: { type: Boolean, default: false },
  highlighted: { type: Boolean, default: false },
  warnings: { type: Array, default: () => [] },
  connectedPorts: { type: Array, default: () => [] },
});

const emit = defineEmits(['dragStart', 'portDown', 'select']);

const { t } = useI18n();
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const meta = computed(() => NODE_TYPES[props.node.type]);
const data = computed(() => props.node.data || {});
const ports = computed(() => portsOf(props.node, t));

const DAY_KEYS = ['0', '1', '2', '3', '4', '5', '6'];
const teamName = id => teams.value.find(team => team.id === id)?.name;
const agentName = id => agents.value.find(agent => agent.id === id)?.name;

const summary = computed(() => {
  const d = data.value;
  switch (props.node.type) {
    case 'start':
      if (d.trigger === 'keyword') {
        return t('OUTSIDER_TOOLS.BOT.SUMMARY.KEYWORD', {
          words: (d.keywords || []).join(', ') || '—',
        });
      }
      return d.trigger === 'new_conversation'
        ? t('OUTSIDER_TOOLS.BOT.SUMMARY.NEW_CONVERSATION')
        : t('OUTSIDER_TOOLS.BOT.SUMMARY.UNASSIGNED', {
            hours: d.cooldown_hours,
          });
    case 'condition': {
      const open = DAY_KEYS.filter(day => d.hours?.[day]?.enabled);
      if (!open.length) return t('OUTSIDER_TOOLS.BOT.SUMMARY.ALWAYS_CLOSED');
      const first = d.hours[open[0]];
      return `${open.map(day => t(`OUTSIDER_TOOLS.BOT.DAYS_SHORT.${day}`)).join(' ')} · ${first.start}–${first.end}`;
    }
    case 'action': {
      const parts = [];
      if (d.team_id) parts.push(`👥 ${teamName(d.team_id) || '—'}`);
      if (d.assignee_id) parts.push(`👤 ${agentName(d.assignee_id) || '—'}`);
      if (d.labels?.length) parts.push(`🏷️ ${d.labels.join(', ')}`);
      if (d.priority)
        parts.push(`⚑ ${t(`OUTSIDER_TOOLS.BOT.PRIORITIES.${d.priority}`)}`);
      if (d.note) parts.push(`📝 ${d.note}`);
      return parts.join(' · ') || t('OUTSIDER_TOOLS.BOT.SUMMARY.NO_ACTION');
    }
    case 'handoff': {
      const target = [teamName(d.team_id), agentName(d.assignee_id)]
        .filter(Boolean)
        .join(' · ');
      return (
        [d.text, target && `→ ${target}`].filter(Boolean).join('\n') ||
        t('OUTSIDER_TOOLS.BOT.SUMMARY.HANDOFF')
      );
    }
    case 'end':
      return d.text || t('OUTSIDER_TOOLS.BOT.SUMMARY.END');
    default:
      return d.text || t('OUTSIDER_TOOLS.BOT.SUMMARY.EMPTY');
  }
});

const badge = computed(() => {
  const d = data.value;
  if (props.node.type === 'menu')
    return t(`OUTSIDER_TOOLS.BOT.STYLES.${d.style}`);
  if (props.node.type === 'message' && d.delay_seconds > 0) {
    return t('OUTSIDER_TOOLS.BOT.SUMMARY.DELAY', { seconds: d.delay_seconds });
  }
  if (props.node.type === 'question' && d.variable) return `{{${d.variable}}}`;
  if (props.node.type === 'end' && d.resolve) {
    return t('OUTSIDER_TOOLS.BOT.SUMMARY.RESOLVES');
  }
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
    class="absolute rounded-xl border bg-n-solid-1 shadow-sm select-none transition-shadow"
    :class="[
      selected
        ? 'border-n-brand ring-2 ring-n-brand/30 shadow-lg z-20'
        : 'border-n-weak hover:shadow-md z-10',
      connecting && node.type !== 'start'
        ? 'outline-dashed outline-2 outline-n-brand/40'
        : '',
      highlighted ? 'ring-4 ring-n-teal-9/40 border-n-teal-9' : '',
    ]"
    :style="style"
    :data-node-id="node.id"
    @pointerdown.stop="emit('select', node.id)"
  >
    <!-- entrada -->
    <span
      v-if="node.type !== 'start'"
      class="absolute -left-[7px] size-3.5 rounded-full border-2 border-n-solid-1 bg-n-slate-9"
      :style="{ top: `${HEADER_HEIGHT / 2 - 7}px` }"
    />
    <!-- cabeçalho: arrasta -->
    <div
      class="flex items-center gap-2 px-3 cursor-grab active:cursor-grabbing rounded-t-xl"
      :style="{ height: `${HEADER_HEIGHT}px` }"
      @pointerdown.stop="emit('dragStart', $event)"
    >
      <span
        class="flex items-center justify-center rounded-md size-6 shrink-0 text-white"
        :class="meta.color"
      >
        <Icon :icon="meta.icon" class="size-3.5" />
      </span>
      <span class="text-sm font-semibold truncate text-n-slate-12">
        {{ t(`OUTSIDER_TOOLS.BOT.TYPES.${node.type}`) }}
      </span>
      <span
        v-if="badge"
        class="px-1.5 py-0.5 ml-auto text-[10px] font-medium rounded-md shrink-0"
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
    <!-- resumo -->
    <div
      class="px-3 pt-1.5 overflow-hidden text-xs leading-[18px] whitespace-pre-line break-words text-n-slate-11 border-t border-n-weak"
      :style="{ height: `${BODY_HEIGHT}px` }"
    >
      <span class="line-clamp-3">{{ summary }}</span>
    </div>
    <!-- saídas -->
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
