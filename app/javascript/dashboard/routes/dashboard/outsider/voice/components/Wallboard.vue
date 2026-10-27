<script setup>
// OUTSIDER: Telefonia > Painel (Entrega 23, refeito na 24; ver app/services/outsider/voice/wallboard.rb). No
// período escolhido (hoje, ontem, semana, mês ou de uma data a outra): os indicadores de ligação com a
// comparação com o período anterior, a meta do mês, ligações dia a dia, por hora e por dia/hora, como
// terminaram, duração das conversas, tempo para atender, a equipe e quem está em ligação agora. Exporta o
// relatório em PDF e as planilhas. O gestor escolhe a equipe toda ou um vendedor; o vendedor vê os próprios
// números. Datas e horas no fuso da telefonia. Atualiza a cada ligação e a cada minuto.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntervalFn, useNow } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PaceBar from './PaceBar.vue';
import CallsChart from './CallsChart.vue';
import KpiTile from './KpiTile.vue';
import OutcomeBars from './OutcomeBars.vue';
import TeamRanking from './TeamRanking.vue';
import WeekHeatmap from './WeekHeatmap.vue';
import {
  downloadBlob,
  formatDate,
  formatDuration,
  formatPercent,
  formatPhone,
  formatTalkTime,
} from '../format';
import { errorMessage } from '../../crm/helpers';
import { useCrmChanges } from '../../crm/live';

const PERIODS = [
  'today',
  'yesterday',
  'week',
  'last_week',
  'month',
  'last_month',
  'custom',
];
const SERIES = ['inbound_answered', 'missed', 'outbound', 'internal'];

const { t } = useI18n();
const now = useNow({ interval: 1000 });

const today = new Date().toLocaleDateString('sv');
const period = ref('today');
const from = ref(today);
const to = ref(today);
const userId = ref(null);
const board = ref(null);
const isLoading = ref(true);
const timelineMetric = ref('calls');
const exportOpen = ref(false);
const exporting = ref('');

const currentUser = useMapGetter('getCurrentUser');

const params = computed(() => ({
  period: period.value,
  user_id: userId.value,
  ...(period.value === 'custom' ? { from: from.value, to: to.value } : {}),
}));

// o vendedor escolhido na lista (gestor) ou a própria pessoa (vendedor)
const selected = computed(() =>
  board.value?.agents.find(agent => agent.id === board.value.user_id)
);
const who = computed(() => {
  if (selected.value) return selected.value;
  if (board.value?.manager) return null;
  return {
    name: currentUser.value.available_name || currentUser.value.name,
    thumbnail: currentUser.value.avatar_url,
  };
});

const summary = computed(() => board.value.summary);
const previous = computed(() => board.value.previous);

const periodText = computed(() => {
  const { from: first, to: last } = board.value.period;
  return first === last
    ? formatDate(first)
    : `${formatDate(first)} – ${formatDate(last)}`;
});
const compareText = computed(() => {
  const { previous_from: first, previous_to: last } = board.value.period;
  return t('OUTSIDER_VOICE.WALLBOARD.COMPARED', {
    period:
      first === last
        ? formatDate(first)
        : `${formatDate(first)} – ${formatDate(last)}`,
  });
});

const tiles = computed(() => {
  const current = summary.value;
  const before = previous.value;
  const tile = (key, value, extra = {}) => ({
    key,
    label: t(`OUTSIDER_VOICE.WALLBOARD.KPI.${key}`),
    value,
    current: current[extra.metric || key.toLowerCase()] ?? null,
    previous: before[extra.metric || key.toLowerCase()] ?? null,
    ...extra,
  });
  return {
    volume: [
      tile('TOTAL', current.total, {
        icon: 'i-lucide-phone',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.TOTAL_HINT', {
          internal: current.internal,
        }),
      }),
      tile('INBOUND', current.inbound, {
        icon: 'i-lucide-phone-incoming',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.INBOUND_HINT', {
          answered: current.inbound_answered,
          missed: current.missed,
        }),
      }),
      tile('OUTBOUND', current.outbound, {
        icon: 'i-lucide-phone-outgoing',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.OUTBOUND_HINT', {
          answered: current.outbound_answered,
        }),
      }),
      tile('MISSED', current.missed, {
        icon: 'i-lucide-phone-missed',
        better: 'down',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.MISSED_HINT', {
          returned: current.returned,
          waiting: board.value.to_return,
        }),
      }),
      tile('CUSTOMERS', current.customers, {
        icon: 'i-lucide-contact',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.CUSTOMERS_HINT'),
      }),
    ],
    quality: [
      tile('ANSWER_RATE', formatPercent(current.answer_rate), {
        points: true,
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.ANSWER_RATE_HINT'),
      }),
      tile('SERVICE_LEVEL', formatPercent(current.service_level), {
        points: true,
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.SERVICE_LEVEL_HINT', {
          seconds: board.value.service_seconds,
        }),
      }),
      tile('CONTACT_RATE', formatPercent(current.contact_rate), {
        points: true,
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.CONTACT_RATE_HINT'),
      }),
      tile('AVERAGE_TALK', formatDuration(current.average_talk), {
        better: 'none',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.AVERAGE_TALK_HINT', {
          longest: formatDuration(current.longest_talk),
        }),
      }),
      tile('AVERAGE_ANSWER', formatDuration(current.average_answer), {
        better: 'down',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.AVERAGE_ANSWER_HINT', {
          longest: formatDuration(current.longest_wait),
        }),
      }),
      tile('TALK', formatTalkTime(current.talk_seconds), {
        metric: 'talk_seconds',
        hint: t('OUTSIDER_VOICE.WALLBOARD.KPI.TALK_HINT'),
      }),
    ],
  };
});

// meta do mês: onde deveria estar hoje e quanto falta por dia útil
const goal = computed(() => {
  const data = board.value?.goal;
  if (!data || (!data.calls && !data.minutes)) return null;
  const { business_days: days, business_days_left: left } = data;
  const missingCalls = Math.max(0, (data.calls || 0) - data.month_calls);
  const missingMinutes = Math.max(0, (data.minutes || 0) - data.month_minutes);
  return {
    ...data,
    pace: days ? (days - left) / days : 0,
    missingCalls,
    missingMinutes,
    perDay: left ? Math.ceil(missingCalls / left) : missingCalls,
  };
});

const seriesLabel = key => t(`OUTSIDER_VOICE.WALLBOARD.SERIES.${key}`);

// dia a dia (ou mês a mês): quantidade por tipo ou minutos em ligação
const timelineChart = computed(() => {
  const timeline = board.value?.timeline;
  if (!timeline) return null;
  const rows = timeline.rows;
  const monthly = timeline.unit === 'month';
  const labels = rows.map(row =>
    monthly ? formatDate(row.date, 'month') : formatDate(row.date, 'day')
  );
  const titles = rows.map(row =>
    monthly ? formatDate(row.date, 'month') : formatDate(row.date, 'weekday')
  );
  const series =
    timelineMetric.value === 'minutes'
      ? [
          {
            key: 'minutes',
            label: seriesLabel('minutes'),
            data: rows.map(row => Math.round(row.talk_seconds / 60)),
          },
        ]
      : SERIES.map(key => ({
          key,
          label: seriesLabel(key),
          data: rows.map(row => row[key]),
        }));
  return { labels, titles, series, monthly };
});

// expediente (8h às 18h) mais as horas que tiveram ligação fora dele
const hourChart = computed(() => {
  const rows = board.value.by_hour;
  const busy = rows
    .filter(row => SERIES.some(key => row[key]))
    .map(row => row.hour);
  const first = Math.min(8, ...busy);
  const last = Math.max(18, ...busy);
  const hours = rows.filter(row => row.hour >= first && row.hour <= last);
  return {
    labels: hours.map(row => `${row.hour}h`),
    series: SERIES.map(key => ({
      key,
      label: seriesLabel(key),
      data: hours.map(row => row[key]),
    })),
  };
});

const bucketLabel = (bucket, unit) => {
  if (bucket.to === null) {
    return t('OUTSIDER_VOICE.WALLBOARD.BUCKETS.MORE', {
      value: unit === 'min' ? bucket.from / 60 : bucket.from,
      unit,
    });
  }
  const scale = unit === 'min' ? 60 : 1;
  return t('OUTSIDER_VOICE.WALLBOARD.BUCKETS.RANGE', {
    from: bucket.from / scale,
    to: bucket.to / scale,
    unit,
  });
};

const talkChart = computed(() => ({
  labels: board.value.talk_buckets.map(bucket => bucketLabel(bucket, 'min')),
  series: [
    {
      key: 'talk',
      label: t('OUTSIDER_VOICE.WALLBOARD.TALK_BUCKETS_SERIES'),
      data: board.value.talk_buckets.map(bucket => bucket.count),
    },
  ],
}));

const waitChart = computed(() => ({
  labels: board.value.wait_buckets.map(bucket => bucketLabel(bucket, 's')),
  series: [
    {
      key: 'wait',
      label: t('OUTSIDER_VOICE.WALLBOARD.WAIT_BUCKETS_SERIES'),
      data: board.value.wait_buckets.map(bucket => bucket.count),
    },
  ],
}));

const agentStatus = agent => {
  if (agent.in_call) return 'in_call';
  return agent.online ? 'online' : 'offline';
};

const STATUS_DOT = {
  in_call: 'bg-n-amber-9',
  online: 'bg-n-teal-9',
  offline: 'bg-n-slate-7',
};

const liveTime = call =>
  call.answered_at
    ? formatDuration((now.value - new Date(call.answered_at)) / 1000)
    : t('OUTSIDER_VOICE.WALLBOARD.RINGING');

const exportItems = computed(() => [
  {
    action: 'export',
    value: 'pdf',
    label: t('OUTSIDER_VOICE.WALLBOARD.EXPORT.PDF'),
    icon: 'i-lucide-file-text',
  },
  {
    action: 'export',
    value: 'calls',
    label: t('OUTSIDER_VOICE.WALLBOARD.EXPORT.CALLS'),
    icon: 'i-lucide-sheet',
  },
  ...(board.value?.manager && !board.value.user_id
    ? [
        {
          action: 'export',
          value: 'agents',
          label: t('OUTSIDER_VOICE.WALLBOARD.EXPORT.AGENTS'),
          icon: 'i-lucide-users',
        },
      ]
    : []),
  ...(board.value?.timeline
    ? [
        {
          action: 'export',
          value: 'days',
          label: t('OUTSIDER_VOICE.WALLBOARD.EXPORT.DAYS'),
          icon: 'i-lucide-calendar-days',
        },
      ]
    : []),
]);

const exportReport = async ({ value }) => {
  exportOpen.value = false;
  exporting.value = value;
  try {
    const response = await VoiceAPI.exportCalls({
      ...params.value,
      kind: value,
    });
    downloadBlob(response);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    exporting.value = '';
  }
};

const load = async () => {
  if (period.value === 'custom' && (!from.value || !to.value)) return;
  try {
    const { data } = await VoiceAPI.getWallboard(params.value);
    board.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

watch(params, () => {
  isLoading.value = true;
  load();
});

useCrmChanges(changes => {
  if (changes.some(({ kind }) => ['call', 'reconnected'].includes(kind))) {
    load();
  }
});
useIntervalFn(load, 60000);
onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex flex-wrap items-center gap-1">
        <button
          v-for="key in PERIODS"
          :key="key"
          type="button"
          class="px-3 py-1.5 text-sm rounded-lg"
          :class="
            period === key
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          :data-testid="`wallboard-period-${key}`"
          @click="period = key"
        >
          {{ t(`OUTSIDER_VOICE.WALLBOARD.PERIODS.${key}`) }}
        </button>
        <span
          v-if="period === 'custom'"
          class="flex items-center gap-1.5 text-sm text-n-slate-11"
        >
          <input
            v-model.lazy="from"
            type="date"
            :max="to"
            class="!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
            data-testid="wallboard-from"
          />
          {{ t('OUTSIDER_VOICE.WALLBOARD.UNTIL') }}
          <input
            v-model.lazy="to"
            type="date"
            :min="from"
            class="!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
            data-testid="wallboard-to"
          />
        </span>
        <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      </div>
      <div class="relative">
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-download"
          :label="t('OUTSIDER_VOICE.WALLBOARD.EXPORT.BUTTON')"
          :is-loading="!!exporting"
          :disabled="!board"
          data-testid="wallboard-export"
          @click="exportOpen = !exportOpen"
        />
        <DropdownMenu
          v-if="exportOpen"
          v-on-click-outside="() => (exportOpen = false)"
          :menu-items="exportItems"
          class="z-30 mt-1 top-full ltr:right-0 rtl:left-0 min-w-64"
          @action="exportReport"
        />
      </div>
    </div>

    <div v-if="board" class="flex flex-col gap-4 lg:flex-row">
      <!-- vendedores (gestor) -->
      <aside
        v-if="board.manager"
        class="flex flex-col overflow-hidden lg:w-64 shrink-0 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2 h-fit"
      >
        <div
          class="px-4 py-2.5 text-xs font-medium border-b border-n-weak text-n-slate-11"
        >
          {{ t('OUTSIDER_VOICE.WALLBOARD.TEAM') }}
        </div>
        <button
          type="button"
          class="flex items-center justify-between gap-2 px-4 py-2 text-left border-b border-n-weak"
          :class="userId ? 'hover:bg-n-alpha-1' : 'bg-n-alpha-2'"
          @click="userId = null"
        >
          <span class="flex items-center gap-2 text-sm text-n-slate-12">
            <Icon icon="i-lucide-users" class="size-4 text-n-slate-11" />
            {{ t('OUTSIDER_VOICE.WALLBOARD.EVERYONE') }}
          </span>
        </button>
        <button
          v-for="agent in board.agents"
          :key="agent.id"
          type="button"
          class="flex items-center justify-between gap-2 px-4 py-2 text-left border-b border-n-weak last:border-0"
          :class="userId === agent.id ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
          data-testid="wallboard-agent"
          @click="userId = agent.id"
        >
          <span class="flex items-center min-w-0 gap-2">
            <span class="relative shrink-0">
              <Avatar
                :name="agent.name"
                :src="agent.thumbnail"
                :size="24"
                rounded-full
              />
              <span
                class="absolute bottom-0 rounded-full size-2 ltr:right-0 rtl:left-0 outline outline-2 outline-n-solid-2"
                :class="STATUS_DOT[agentStatus(agent)]"
                :title="
                  t(`OUTSIDER_VOICE.WALLBOARD.STATUS.${agentStatus(agent)}`)
                "
              />
            </span>
            <span class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ agent.name }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ t(`OUTSIDER_VOICE.WALLBOARD.STATUS.${agentStatus(agent)}`) }}
                <template v-if="agent.extension">
                  ·
                  {{
                    t('OUTSIDER_VOICE.WALLBOARD.EXTENSION', {
                      extension: agent.extension,
                    })
                  }}
                </template>
              </span>
            </span>
          </span>
          <span class="text-sm font-medium tabular-nums text-n-slate-12">
            {{ agent.total }}
          </span>
        </button>
      </aside>

      <div class="flex flex-col flex-1 min-w-0 gap-4">
        <!-- quem e o período -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center min-w-0 gap-3">
            <Avatar
              v-if="who"
              :name="who.name"
              :src="who.thumbnail"
              :size="40"
              rounded-full
            />
            <span
              v-else
              class="flex items-center justify-center rounded-full size-10 bg-n-alpha-2"
            >
              <Icon icon="i-lucide-users" class="size-5 text-n-slate-11" />
            </span>
            <span class="flex flex-col min-w-0">
              <span
                class="text-base font-medium truncate text-n-slate-12"
                data-testid="wallboard-who"
              >
                {{ who?.name || t('OUTSIDER_VOICE.WALLBOARD.EVERYONE') }}
              </span>
              <span
                class="text-xs text-n-slate-11"
                data-testid="wallboard-period-text"
              >
                {{ periodText }} · {{ compareText }}
              </span>
            </span>
          </div>
          <span
            v-if="selected"
            class="flex items-center gap-1.5 text-xs text-n-slate-11"
          >
            <span
              class="rounded-full size-2"
              :class="STATUS_DOT[agentStatus(selected)]"
            />
            {{ t(`OUTSIDER_VOICE.WALLBOARD.STATUS.${agentStatus(selected)}`) }}
          </span>
        </div>

        <!-- volume -->
        <div class="grid gap-3 grid-cols-2 md:grid-cols-3 xl:grid-cols-5">
          <KpiTile
            v-for="tile in tiles.volume"
            :key="tile.key"
            v-bind="tile"
            :data-testid="`wallboard-${tile.key.toLowerCase()}`"
          />
        </div>
        <!-- qualidade e tempos -->
        <div class="grid gap-3 grid-cols-2 md:grid-cols-3 2xl:grid-cols-6">
          <KpiTile
            v-for="tile in tiles.quality"
            :key="tile.key"
            v-bind="tile"
            :data-testid="`wallboard-${tile.key.toLowerCase()}`"
          />
        </div>

        <!-- meta do mês de um vendedor -->
        <div
          v-if="board.user_id"
          class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          data-testid="wallboard-goal"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.WALLBOARD.GOAL.TITLE') }}
          </h3>
          <p v-if="!goal" class="mb-0 text-sm text-n-slate-11">
            {{ t('OUTSIDER_VOICE.WALLBOARD.GOAL.NO_GOAL') }}
          </p>
          <template v-else>
            <div class="grid gap-4 sm:grid-cols-2">
              <div class="flex flex-col gap-1.5">
                <span class="text-xs text-n-slate-11">
                  {{ t('OUTSIDER_VOICE.WALLBOARD.GOAL.CALLS') }}
                </span>
                <PaceBar
                  :value="goal.month_calls"
                  :goal="goal.calls || null"
                  :pace="goal.pace"
                />
              </div>
              <div class="flex flex-col gap-1.5">
                <span class="text-xs text-n-slate-11">
                  {{ t('OUTSIDER_VOICE.WALLBOARD.GOAL.MINUTES') }}
                </span>
                <PaceBar
                  :value="goal.month_minutes"
                  :goal="goal.minutes || null"
                  :pace="goal.pace"
                />
              </div>
            </div>
            <p class="mb-0 text-sm text-n-slate-12">
              {{
                goal.missingCalls || goal.missingMinutes
                  ? t('OUTSIDER_VOICE.WALLBOARD.GOAL.MISSING', {
                      calls: goal.missingCalls,
                      minutes: goal.missingMinutes,
                      perDay: goal.perDay,
                      days: goal.business_days_left,
                    })
                  : t('OUTSIDER_VOICE.WALLBOARD.GOAL.REACHED')
              }}
            </p>
          </template>
        </div>

        <!-- dia a dia -->
        <div
          v-if="timelineChart"
          class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          data-testid="wallboard-timeline"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{
                timelineChart.monthly
                  ? t('OUTSIDER_VOICE.WALLBOARD.BY_MONTH')
                  : t('OUTSIDER_VOICE.WALLBOARD.BY_DAY')
              }}
            </h3>
            <div class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-1">
              <button
                v-for="metric in ['calls', 'minutes']"
                :key="metric"
                type="button"
                class="px-2.5 py-1 text-xs rounded-md"
                :class="
                  timelineMetric === metric
                    ? 'bg-n-solid-3 text-n-slate-12 font-medium shadow-sm'
                    : 'text-n-slate-11'
                "
                @click="timelineMetric = metric"
              >
                {{ t(`OUTSIDER_VOICE.WALLBOARD.METRICS.${metric}`) }}
              </button>
            </div>
          </div>
          <CallsChart
            :labels="timelineChart.labels"
            :titles="timelineChart.titles"
            :series="timelineChart.series"
            :total-label="t('OUTSIDER_VOICE.WALLBOARD.KPI.TOTAL')"
            height="h-64"
          />
        </div>

        <div class="grid gap-4 xl:grid-cols-3">
          <div
            class="flex flex-col gap-3 p-4 xl:col-span-2 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
            data-testid="wallboard-by-hour"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.WALLBOARD.BY_HOUR') }}
            </h3>
            <p v-if="!summary.total" class="mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_VOICE.WALLBOARD.EMPTY') }}
            </p>
            <CallsChart
              v-else
              :labels="hourChart.labels"
              :series="hourChart.series"
              :total-label="t('OUTSIDER_VOICE.WALLBOARD.KPI.TOTAL')"
            />
          </div>

          <!-- em ligação agora -->
          <div
            class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
            data-testid="wallboard-live"
          >
            <h3
              class="flex items-center justify-between mb-0 text-sm font-medium text-n-slate-12"
            >
              {{ t('OUTSIDER_VOICE.WALLBOARD.LIVE') }}
              <span
                v-if="board.live.length"
                class="px-2 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
              >
                {{ board.live.length }}
              </span>
            </h3>
            <p v-if="!board.live.length" class="mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_VOICE.WALLBOARD.LIVE_EMPTY') }}
            </p>
            <div
              v-for="call in board.live"
              :key="call.id"
              class="flex items-center gap-2 text-sm"
            >
              <Icon
                :icon="
                  call.direction === 'inbound'
                    ? 'i-lucide-phone-incoming'
                    : 'i-lucide-phone-outgoing'
                "
                class="size-4 shrink-0"
                :class="
                  call.status === 'ringing'
                    ? 'text-n-amber-11'
                    : 'text-n-teal-11'
                "
              />
              <span class="flex flex-col flex-1 min-w-0">
                <span class="truncate text-n-slate-12">
                  {{ call.user || t('OUTSIDER_VOICE.WALLBOARD.RINGING') }}
                </span>
                <span class="text-xs truncate text-n-slate-11">
                  {{ call.customer || formatPhone(call.number) }}
                </span>
              </span>
              <span class="text-xs tabular-nums text-n-slate-11">
                {{ liveTime(call) }}
              </span>
            </div>
          </div>
        </div>

        <div class="grid gap-4 xl:grid-cols-3">
          <div
            class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
            data-testid="wallboard-outcomes"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.WALLBOARD.OUTCOMES.TITLE') }}
            </h3>
            <OutcomeBars :summary="summary" />
          </div>
          <div
            class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.WALLBOARD.TALK_BUCKETS') }}
            </h3>
            <CallsChart
              :labels="talkChart.labels"
              :series="talkChart.series"
              height="h-44"
            />
          </div>
          <div
            class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.WALLBOARD.WAIT_BUCKETS') }}
            </h3>
            <CallsChart
              :labels="waitChart.labels"
              :series="waitChart.series"
              height="h-44"
            />
          </div>
        </div>

        <!-- equipe (gestor vendo todos) -->
        <div
          v-if="board.manager && !board.user_id && board.agents.length"
          class="flex flex-col gap-2 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          data-testid="wallboard-ranking"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.WALLBOARD.RANKING.TITLE') }}
          </h3>
          <TeamRanking :agents="board.agents" @pick="userId = $event" />
        </div>

        <div
          v-if="!board.period.single_day"
          class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.WALLBOARD.HEATMAP') }}
          </h3>
          <WeekHeatmap :grid="board.by_weekday_hour" />
        </div>

        <p class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_VOICE.WALLBOARD.ZONE', { zone: board.period.zone }) }}
        </p>
      </div>
    </div>
  </div>
</template>
