<script setup>
// OUTSIDER: mapa do Brasil no Painel da Telefonia (Entrega 25; ver app/services/outsider/voice/call_breakdown.rb):
// cada estado com a cor mais forte quanto mais ligações com clientes dele (pelo DDD do número), uma caixa
// para as internacionais e, ao lado, a lista dos estados (a mesma informação em texto). Passar o mouse
// mostra feitas, recebidas, atendidas, minutos e custo.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { BRAZIL_STATES, BRAZIL_VIEWBOX } from './brazilMap';
import { formatMoney, formatTalkTime } from '../format';

const props = defineProps({
  // { states: { UF: resumo }, international: resumo, unknown: n }
  regions: { type: Object, required: true },
});

const { t } = useI18n();

// uma cor só, do claro ao escuro (0 ligações fica cinza)
const SHADES = [
  'fill-n-slate-3',
  'fill-n-blue-4',
  'fill-n-blue-6',
  'fill-n-blue-8',
  'fill-n-blue-10',
];
const SWATCHES = [
  'bg-n-slate-3',
  'bg-n-blue-4',
  'bg-n-blue-6',
  'bg-n-blue-8',
  'bg-n-blue-10',
];

const hovered = ref(null);
const pointer = ref({ x: 0, y: 0 });
const box = ref(null);

const states = computed(() => props.regions.states || {});
const international = computed(() => props.regions.international || {});

const max = computed(() =>
  Math.max(
    1,
    ...Object.values(states.value).map(row => row.calls),
    international.value.calls || 0
  )
);

// escala pela raiz: um estado com muitas ligações não apaga a diferença entre os outros
const step = count =>
  count
    ? Math.min(4, Math.max(1, Math.ceil(Math.sqrt(count / max.value) * 4)))
    : 0;

// limites de cada tom, para a legenda: "1–7", "8–31"...
const legend = computed(() =>
  [1, 2, 3, 4]
    .map(index => {
      const from = Math.floor(max.value * ((index - 1) / 4) ** 2) + 1;
      const to = Math.floor(max.value * (index / 4) ** 2);
      return {
        swatch: SWATCHES[index],
        to,
        text: from >= to ? String(to) : `${from}–${to}`,
      };
    })
    .filter(
      (item, index) => item.to >= Math.floor(max.value * (index / 4) ** 2) + 1
    )
);

// o DF por último: o contorno de Goiás tem o buraco dele
const PATHS = Object.entries(BRAZIL_STATES)
  .sort(([a], [b]) => (a === 'DF') - (b === 'DF'))
  .map(([uf, state]) => ({ uf, path: state.path }));

const ranked = computed(() =>
  Object.entries(states.value)
    .map(([uf, row]) => ({ uf, name: BRAZIL_STATES[uf]?.name || uf, ...row }))
    .sort((a, b) => b.calls - a.calls)
);

const tooltip = computed(() => {
  if (!hovered.value) return null;
  if (hovered.value === 'INT') {
    return {
      title: t('OUTSIDER_VOICE.WALLBOARD.MAP.INTERNATIONAL'),
      ...international.value,
    };
  }
  return {
    title: BRAZIL_STATES[hovered.value]?.name || hovered.value,
    calls: 0,
    ...states.value[hovered.value],
  };
});

const track = (key, event) => {
  hovered.value = key;
  const rect = box.value?.getBoundingClientRect();
  if (rect) {
    pointer.value = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 lg:flex-row">
    <div
      ref="box"
      class="relative flex-1 min-w-0 lg:max-w-xl"
      @mouseleave="hovered = null"
    >
      <svg
        :viewBox="BRAZIL_VIEWBOX"
        class="w-full h-auto max-h-[28rem]"
        role="img"
        :aria-label="t('OUTSIDER_VOICE.WALLBOARD.MAP.TITLE')"
        data-testid="wallboard-map"
      >
        <path
          v-for="{ uf, path } in PATHS"
          :key="uf"
          :d="path"
          class="transition-[fill] stroke-n-solid-2 cursor-default"
          :class="SHADES[step(states[uf]?.calls || 0)]"
          stroke-width="0.8"
          stroke-linejoin="round"
          :data-uf="uf"
          @mousemove="track(uf, $event)"
        />
        <!-- contorno do estado com o mouse, por cima dos vizinhos -->
        <path
          v-if="BRAZIL_STATES[hovered]"
          :d="BRAZIL_STATES[hovered].path"
          fill="none"
          class="pointer-events-none stroke-n-slate-12"
          stroke-width="1.6"
          stroke-linejoin="round"
        />
      </svg>

      <!-- internacionais -->
      <button
        type="button"
        class="absolute bottom-2 ltr:right-2 rtl:left-2 flex items-center gap-2 px-3 py-2 text-left rounded-lg outline outline-1 -outline-offset-1 bg-n-solid-2"
        :class="hovered === 'INT' ? 'outline-n-slate-12' : 'outline-n-weak'"
        data-testid="wallboard-map-international"
        @mousemove="track('INT', $event)"
        @focus="hovered = 'INT'"
        @blur="hovered = null"
      >
        <span
          class="flex items-center justify-center rounded-md size-8"
          :class="SWATCHES[step(international.calls || 0)]"
        >
          <Icon
            icon="i-lucide-globe"
            class="size-4"
            :class="
              step(international.calls || 0) > 2
                ? 'text-white'
                : 'text-n-slate-12'
            "
          />
        </span>
        <span class="flex flex-col">
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.WALLBOARD.MAP.INTERNATIONAL') }}
          </span>
          <span class="text-sm font-medium tabular-nums text-n-slate-12">
            {{
              t('OUTSIDER_VOICE.WALLBOARD.MAP.CALLS', international.calls || 0)
            }}
          </span>
        </span>
      </button>

      <div
        v-if="tooltip"
        class="absolute z-10 flex flex-col gap-0.5 px-3 py-2 text-xs rounded-lg shadow-lg pointer-events-none min-w-44 bg-n-solid-3 outline outline-1 outline-n-container"
        :style="{
          left: `${Math.min(pointer.x + 14, (box?.clientWidth || 0) - 190)}px`,
          top: `${Math.max(0, pointer.y - 10)}px`,
        }"
        data-testid="wallboard-map-tooltip"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ tooltip.title }}
        </span>
        <span class="text-n-slate-12 tabular-nums">
          {{ t('OUTSIDER_VOICE.WALLBOARD.MAP.CALLS', tooltip.calls || 0) }}
        </span>
        <template v-if="tooltip.calls">
          <span class="text-n-slate-11 tabular-nums">
            {{
              t('OUTSIDER_VOICE.WALLBOARD.MAP.SPLIT', {
                outbound: tooltip.outbound,
                inbound: tooltip.inbound,
                answered: tooltip.answered,
              })
            }}
          </span>
          <span class="text-n-slate-11 tabular-nums">
            {{ formatTalkTime(tooltip.talk_seconds) }} ·
            {{ formatMoney(tooltip.cost) }}
          </span>
        </template>
      </div>
    </div>

    <div class="flex flex-col gap-3 lg:w-72 shrink-0">
      <div
        class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-n-slate-11"
      >
        <span class="flex items-center gap-1">
          <span class="rounded-sm size-3 bg-n-slate-3" />
          {{ t('OUTSIDER_VOICE.WALLBOARD.MAP.NONE') }}
        </span>
        <span
          v-for="item in legend"
          :key="item.text"
          class="flex items-center gap-1 tabular-nums"
        >
          <span class="rounded-sm size-3" :class="item.swatch" />
          {{ item.text }}
        </span>
      </div>
      <p v-if="!ranked.length" class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_VOICE.WALLBOARD.MAP.EMPTY') }}
      </p>
      <ol
        v-else
        class="flex flex-col gap-1.5 mb-0 overflow-y-auto list-none max-h-80"
        data-testid="wallboard-map-list"
      >
        <li
          v-for="row in ranked"
          :key="row.uf"
          class="flex items-center gap-2 px-2 py-1 text-sm rounded-md"
          :class="hovered === row.uf ? 'bg-n-alpha-2' : ''"
          @mouseenter="hovered = row.uf"
          @mouseleave="hovered = null"
        >
          <span class="w-7 text-xs font-medium text-n-slate-11">
            {{ row.uf }}
          </span>
          <span class="flex flex-col flex-1 min-w-0 gap-1">
            <span class="truncate text-n-slate-12">{{ row.name }}</span>
            <span class="h-1 rounded-full bg-n-alpha-2">
              <span
                class="block h-full rounded-full bg-n-blue-9"
                :style="{ width: `${(row.calls * 100) / max}%` }"
              />
            </span>
          </span>
          <span class="flex flex-col items-end">
            <span class="font-medium tabular-nums text-n-slate-12">
              {{ row.calls }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              {{ formatMoney(row.cost) }}
            </span>
          </span>
        </li>
      </ol>
      <p v-if="regions.unknown" class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.WALLBOARD.MAP.UNKNOWN', regions.unknown) }}
      </p>
    </div>
  </div>
</template>
