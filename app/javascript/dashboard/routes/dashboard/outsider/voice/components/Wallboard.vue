<script setup>
// OUTSIDER: Telefonia > Painel (Entrega 23; ver app/services/outsider/voice/wallboard.rb). No período
// escolhido: quantas ligações (recebidas, feitas, entre ramais), os tempos, a meta do mês, ligações por hora
// e por dia/hora e quem está em ligação agora. O gestor escolhe a equipe toda ou um vendedor na lista ao
// lado; o vendedor vê os próprios números. Atualiza a cada ligação e a cada minuto (quem está conectado).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntervalFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PaceBar from './PaceBar.vue';
import HourChart from './HourChart.vue';
import WeekHeatmap from './WeekHeatmap.vue';
import { formatDuration, formatPhone, formatTalkTime } from '../format';
import { errorMessage } from '../../crm/helpers';
import { useCrmChanges } from '../../crm/live';

defineProps({
  access: { type: Object, required: true },
});

const PERIODS = ['today', 'week', 'month', 'last_month'];
const ZONE = Intl.DateTimeFormat().resolvedOptions().timeZone;

const { t } = useI18n();

const period = ref('today');
const userId = ref(null);
const board = ref(null);
const isLoading = ref(true);

const currentUser = useMapGetter('getCurrentUser');

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

const counters = computed(() => {
  const summary = board.value.summary;
  return [
    {
      key: 'TOTAL',
      icon: 'i-lucide-phone',
      value: summary.total,
      hint: t('OUTSIDER_VOICE.WALLBOARD.COUNTERS.TOTAL_HINT'),
    },
    {
      key: 'INBOUND',
      icon: 'i-lucide-phone-incoming',
      value: summary.inbound,
      hint: t('OUTSIDER_VOICE.WALLBOARD.COUNTERS.INBOUND_HINT', {
        answered: summary.inbound_answered,
        missed: summary.missed,
      }),
    },
    {
      key: 'OUTBOUND',
      icon: 'i-lucide-phone-outgoing',
      value: summary.outbound,
      hint: t('OUTSIDER_VOICE.WALLBOARD.COUNTERS.OUTBOUND_HINT', {
        answered: summary.outbound_answered,
      }),
    },
    {
      key: 'INTERNAL',
      icon: 'i-lucide-users',
      value: summary.internal,
      hint: t('OUTSIDER_VOICE.WALLBOARD.COUNTERS.INTERNAL_HINT'),
    },
  ];
});

const times = computed(() => {
  const summary = board.value.summary;
  return [
    {
      key: 'AVERAGE_TALK',
      value: formatDuration(summary.average_talk),
    },
    { key: 'LONGEST', value: formatDuration(summary.longest_talk) },
    { key: 'TALK', value: formatTalkTime(summary.talk_seconds) },
    {
      key: 'AVERAGE_ANSWER',
      value: formatDuration(summary.average_answer),
    },
    { key: 'TO_RETURN', value: board.value.to_return },
  ];
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

const agentStatus = agent => {
  if (agent.in_call) return 'in_call';
  return agent.online ? 'online' : 'offline';
};

const STATUS_DOT = {
  in_call: 'bg-n-amber-9',
  online: 'bg-n-teal-9',
  offline: 'bg-n-slate-7',
};

const load = async () => {
  try {
    const { data } = await VoiceAPI.getWallboard({
      period: period.value,
      user_id: userId.value,
      zone: ZONE,
    });
    board.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

watch([period, userId], () => {
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
    <div class="flex flex-wrap items-center gap-2">
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
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
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
              <span
                v-if="agent.extension"
                class="text-xs truncate text-n-slate-11"
              >
                {{
                  t('OUTSIDER_VOICE.WALLBOARD.EXTENSION', {
                    extension: agent.extension,
                  })
                }}
              </span>
            </span>
          </span>
          <span class="text-sm font-medium tabular-nums text-n-slate-12">
            {{ agent.total }}
          </span>
        </button>
      </aside>

      <div class="flex flex-col flex-1 min-w-0 gap-4">
        <!-- quem e os números do período -->
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <div
            class="flex items-center gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          >
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
                v-if="selected"
                class="flex items-center gap-1.5 text-xs text-n-slate-11"
              >
                <span
                  class="rounded-full size-2"
                  :class="STATUS_DOT[agentStatus(selected)]"
                />
                {{
                  t(`OUTSIDER_VOICE.WALLBOARD.STATUS.${agentStatus(selected)}`)
                }}
              </span>
            </span>
          </div>
          <div
            v-for="counter in counters"
            :key="counter.key"
            class="flex flex-col gap-1 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
            :data-testid="`wallboard-${counter.key.toLowerCase()}`"
          >
            <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
              <Icon :icon="counter.icon" class="size-3.5" />
              {{ t(`OUTSIDER_VOICE.WALLBOARD.COUNTERS.${counter.key}`) }}
            </span>
            <span class="text-2xl font-medium tabular-nums text-n-slate-12">
              {{ counter.value }}
            </span>
            <span class="text-xs text-n-slate-11">{{ counter.hint }}</span>
          </div>
        </div>

        <div
          class="grid grid-cols-2 gap-px overflow-hidden sm:grid-cols-5 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-weak"
        >
          <div
            v-for="item in times"
            :key="item.key"
            class="flex flex-col gap-0.5 px-4 py-3 bg-n-solid-2"
          >
            <span class="text-xs text-n-slate-11">
              {{ t(`OUTSIDER_VOICE.WALLBOARD.TIMES.${item.key}`) }}
            </span>
            <span class="text-lg font-medium tabular-nums text-n-slate-12">
              {{ item.value }}
            </span>
          </div>
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

        <div class="grid gap-4 xl:grid-cols-3">
          <div
            class="flex flex-col gap-3 p-4 xl:col-span-2 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.WALLBOARD.BY_HOUR') }}
            </h3>
            <p
              v-if="!board.summary.total"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('OUTSIDER_VOICE.WALLBOARD.EMPTY') }}
            </p>
            <HourChart v-else :rows="board.by_hour" />
          </div>

          <!-- em ligação agora -->
          <div
            class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
            data-testid="wallboard-live"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.WALLBOARD.LIVE') }}
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
                  call.status === 'ringing' ? 'text-n-amber-11' : 'text-n-teal-11'
                "
              />
              <span class="flex flex-col min-w-0">
                <span class="truncate text-n-slate-12">
                  {{ call.user || t('OUTSIDER_VOICE.WALLBOARD.RINGING') }}
                </span>
                <span class="text-xs truncate text-n-slate-11">
                  {{ call.customer || formatPhone(call.number) }}
                </span>
              </span>
            </div>
          </div>
        </div>

        <div
          v-if="period !== 'today'"
          class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.WALLBOARD.HEATMAP') }}
          </h3>
          <WeekHeatmap :grid="board.by_weekday_hour" />
        </div>
      </div>
    </div>
  </div>
</template>
