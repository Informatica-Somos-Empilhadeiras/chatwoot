<script setup>
// OUTSIDER: CRM > Ligações (Entrega 22; ver app/services/outsider/voice/stats.rb). Números do mês e de hoje,
// a meta de ligação de cada vendedor (com o ritmo esperado até hoje), a fila de perdidas para retornar com
// 1 clique e o histórico do mês. O vendedor vê só os próprios números; atualiza sozinho a cada ligação.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CallButton from '../../../voice/CallButton.vue';
import PaceBar from './PaceBar.vue';
import {
  formatPhone,
  formatDuration,
  formatTalkTime,
} from '../../../voice/format';
import {
  currentMonth,
  errorMessage,
  formatDateTime,
  formatMonth,
  shiftMonth,
} from '../../helpers';
import { useCrmChanges } from '../../live';

defineProps({
  access: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const STATUS_COLORS = {
  answered: 'bg-n-teal-3 text-n-teal-11',
  missed: 'bg-n-ruby-3 text-n-ruby-11',
  unanswered: 'bg-n-amber-3 text-n-amber-11',
  busy: 'bg-n-amber-3 text-n-amber-11',
  failed: 'bg-n-slate-3 text-n-slate-11',
  ringing: 'bg-n-blue-3 text-n-blue-11',
};

const month = ref(currentMonth());
const stats = ref(null);
const toReturn = ref([]);
const calls = ref([]);
const total = ref(0);
const page = ref(1);
const filters = ref({ direction: '', status: '', user_id: '' });
const isLoading = ref(true);
const isLoadingMore = ref(false);

const minutes = seconds => Math.round((seconds || 0) / 60);

const pace = computed(() => {
  const { business_days: days, business_days_left: left } = stats.value;
  return days ? (days - left) / days : 0;
});

const dayGoal = goal =>
  goal ? Math.ceil(goal / stats.value.business_days) : 0;

const kpis = computed(() => {
  const { totals, today } = stats.value;
  return [
    {
      key: 'OUTBOUND',
      icon: 'i-lucide-phone-outgoing',
      value: totals.outbound,
      hint: t('OUTSIDER_VOICE.PANEL.KPIS.OUTBOUND_HINT', {
        count: totals.outbound_answered,
      }),
      today: today.outbound,
    },
    {
      key: 'INBOUND',
      icon: 'i-lucide-phone-incoming',
      value: totals.inbound_answered,
      hint: t('OUTSIDER_VOICE.PANEL.KPIS.INBOUND_HINT', {
        count: totals.inbound,
      }),
      today: today.inbound_answered,
    },
    {
      key: 'MISSED',
      icon: 'i-lucide-phone-missed',
      value: totals.missed,
      hint: t('OUTSIDER_VOICE.PANEL.KPIS.MISSED_HINT', {
        count: totals.to_return,
      }),
      today: today.missed,
    },
    {
      key: 'TALK',
      icon: 'i-lucide-timer',
      value: formatTalkTime(totals.talk_seconds),
      hint: t('OUTSIDER_VOICE.PANEL.KPIS.TALK_HINT'),
      today: formatTalkTime(today.talk_seconds),
    },
  ];
});

const directionOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_DIRECTIONS') },
  ...['outbound', 'inbound'].map(value => ({
    value,
    label: t(`OUTSIDER_VOICE.PANEL.HISTORY.DIRECTIONS.${value}`),
  })),
]);
const statusOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_STATUS') },
  ...['answered', 'missed', 'unanswered', 'busy', 'failed'].map(value => ({
    value,
    label: t(`OUTSIDER_VOICE.PANEL.HISTORY.STATUS.${value}`),
  })),
]);
const sellerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_SELLERS') },
  ...(stats.value?.sellers || []).map(seller => ({
    value: seller.id,
    label: seller.name,
  })),
]);

const customerName = call =>
  call.contact_name || formatPhone(call.customer_number);

const openDeal = id =>
  router.push({
    params: { ...route.params, tab: 'opportunities' },
    query: { negocio: id },
  });

const openGoals = () =>
  router.push({
    params: { ...route.params, tab: 'settings' },
    query: { secao: 'call_goals' },
  });

const loadCalls = async (more = false) => {
  page.value = more ? page.value + 1 : 1;
  const { data } = await VoiceAPI.getCalls({
    month: month.value,
    page: page.value,
    ...filters.value,
  });
  calls.value = more ? [...calls.value, ...data.payload] : data.payload;
  total.value = data.meta.total;
};

const load = async () => {
  try {
    const [statsResponse, returnResponse] = await Promise.all([
      VoiceAPI.getStats(month.value),
      VoiceAPI.getCalls({ to_return: 1 }),
      loadCalls(),
    ]);
    stats.value = statsResponse.data;
    toReturn.value = returnResponse.data.payload;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  isLoadingMore.value = true;
  try {
    await loadCalls(true);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoadingMore.value = false;
  }
};

watch(month, () => {
  isLoading.value = true;
  load();
});
watch(filters, () => loadCalls().catch(() => {}), { deep: true });

// cada ligação que começa, é atendida ou termina avisa ao vivo
useCrmChanges(changes => {
  if (changes.some(({ kind }) => ['call', 'reconnected'].includes(kind))) {
    load();
  }
});

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-wrap items-center gap-2">
      <Button
        icon="i-lucide-chevron-left"
        size="sm"
        variant="faded"
        color="slate"
        :aria-label="t('OUTSIDER_CRM.GOALS.PREVIOUS')"
        @click="month = shiftMonth(month, -1)"
      />
      <span
        class="inline-block px-1 text-sm font-medium first-letter:uppercase text-n-slate-12"
      >
        {{ formatMonth(month) }}
      </span>
      <Button
        icon="i-lucide-chevron-right"
        size="sm"
        variant="faded"
        color="slate"
        :aria-label="t('OUTSIDER_CRM.GOALS.NEXT')"
        @click="month = shiftMonth(month, 1)"
      />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <span v-if="stats" class="text-xs text-n-slate-11">
        {{
          t('OUTSIDER_VOICE.PANEL.SELLERS.DAYS_LEFT', {
            left: stats.business_days_left,
            total: stats.business_days,
          })
        }}
      </span>
    </div>

    <template v-if="stats">
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div
          v-for="kpi in kpis"
          :key="kpi.key"
          class="flex flex-col gap-1 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          :data-testid="`calls-kpi-${kpi.key.toLowerCase()}`"
        >
          <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
            <Icon :icon="kpi.icon" class="size-3.5" />
            {{ t(`OUTSIDER_VOICE.PANEL.KPIS.${kpi.key}`) }}
          </span>
          <span class="text-2xl font-medium tabular-nums text-n-slate-12">
            {{ kpi.value }}
          </span>
          <span class="text-xs text-n-slate-11">{{ kpi.hint }}</span>
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PANEL.KPIS.TODAY', { value: kpi.today }) }}
          </span>
        </div>
      </div>

      <!-- metas por vendedor -->
      <section
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div
          class="flex flex-wrap items-start justify-between gap-3 px-4 py-3 border-b border-n-weak"
        >
          <div class="flex flex-col gap-0.5 max-w-2xl">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.PANEL.SELLERS.TITLE') }}
            </h3>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('OUTSIDER_VOICE.PANEL.SELLERS.DESCRIPTION') }}
            </p>
          </div>
          <Button
            v-if="access.administrator"
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-target"
            :label="t('OUTSIDER_VOICE.PANEL.SELLERS.SET_GOALS')"
            @click="openGoals"
          />
        </div>
        <p
          v-if="!stats.sellers.length"
          class="px-4 py-3 mb-0 text-sm text-n-slate-11"
        >
          {{ t('OUTSIDER_VOICE.PANEL.SELLERS.EMPTY') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm min-w-[46rem]">
            <thead>
              <tr class="text-xs text-left text-n-slate-11">
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.SELLERS.SELLER') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.SELLERS.TODAY') }}
                </th>
                <th class="w-56 px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.SELLERS.CALLS') }}
                </th>
                <th class="w-56 px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.SELLERS.MINUTES') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="seller in stats.sellers"
                :key="seller.id"
                class="border-t border-n-weak"
                data-testid="calls-seller-row"
              >
                <td class="px-4 py-3">
                  <span class="flex items-center gap-2 min-w-0">
                    <span class="relative shrink-0">
                      <Avatar
                        :name="seller.name"
                        :src="seller.thumbnail"
                        :size="28"
                        rounded-full
                      />
                      <span
                        class="absolute bottom-0 rounded-full size-2.5 ltr:right-0 rtl:left-0 outline outline-2 outline-n-solid-2"
                        :class="seller.online ? 'bg-n-teal-9' : 'bg-n-slate-7'"
                        :title="
                          seller.online
                            ? t('OUTSIDER_VOICE.PANEL.SELLERS.ONLINE')
                            : t('OUTSIDER_VOICE.PANEL.SELLERS.OFFLINE')
                        "
                      />
                    </span>
                    <span class="flex flex-col min-w-0">
                      <span class="truncate text-n-slate-12">
                        {{ seller.name }}
                      </span>
                      <span
                        v-if="seller.extension"
                        class="text-xs truncate text-n-slate-11"
                      >
                        {{
                          t('OUTSIDER_VOICE.PANEL.SELLERS.EXTENSION', {
                            extension: seller.extension,
                          })
                        }}
                        <template v-if="seller.state">
                          · {{ seller.state }}
                        </template>
                      </span>
                    </span>
                  </span>
                </td>
                <td class="px-4 py-3 text-xs tabular-nums">
                  <div class="text-n-slate-12">
                    {{
                      t('OUTSIDER_VOICE.PANEL.SELLERS.TODAY_VALUE', {
                        calls: seller.today.outbound,
                        minutes: minutes(seller.today.talk_seconds),
                      })
                    }}
                  </div>
                  <div
                    v-if="seller.goal.calls || seller.goal.minutes"
                    class="text-n-slate-11"
                  >
                    {{
                      t('OUTSIDER_VOICE.PANEL.SELLERS.DAY_GOAL', {
                        calls: dayGoal(seller.goal.calls),
                        minutes: dayGoal(seller.goal.minutes),
                      })
                    }}
                  </div>
                </td>
                <td class="px-4 py-3">
                  <PaceBar
                    :value="seller.month.outbound"
                    :goal="seller.goal.calls || null"
                    :pace="pace"
                  />
                </td>
                <td class="px-4 py-3">
                  <PaceBar
                    :value="minutes(seller.month.talk_seconds)"
                    :goal="seller.goal.minutes || null"
                    :pace="pace"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- perdidas para retornar -->
      <section
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex flex-col gap-0.5 px-4 py-3 border-b border-n-weak">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PANEL.RETURN.TITLE') }}
            <span
              v-if="toReturn.length"
              class="px-1.5 py-0.5 ml-1 text-xs rounded-md bg-n-ruby-3 text-n-ruby-11"
            >
              {{ toReturn.length }}
            </span>
          </h3>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.PANEL.RETURN.DESCRIPTION') }}
          </p>
        </div>
        <p
          v-if="!toReturn.length"
          class="px-4 py-3 mb-0 text-sm text-n-slate-11"
        >
          {{ t('OUTSIDER_VOICE.PANEL.RETURN.EMPTY') }}
        </p>
        <div
          v-for="call in toReturn"
          :key="call.id"
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-2.5 border-b border-n-weak last:border-0"
          data-testid="calls-return-row"
        >
          <span class="flex items-center min-w-0 gap-3">
            <Icon
              icon="i-lucide-phone-missed"
              class="size-4 shrink-0 text-n-ruby-11"
            />
            <span class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ customerName(call) }}
                <span v-if="call.contact_name" class="text-xs text-n-slate-11">
                  {{ formatPhone(call.customer_number) }}
                </span>
              </span>
              <span class="text-xs text-n-slate-11">
                {{ formatDateTime(call.started_at, t) }}
                <template v-if="call.did">
                  ·
                  {{
                    t('OUTSIDER_VOICE.PANEL.RETURN.TO_NUMBER', {
                      number: formatPhone(call.did),
                    })
                  }}
                </template>
              </span>
            </span>
          </span>
          <span class="flex items-center gap-2">
            <Button
              v-if="call.opportunity_id"
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-kanban"
              :label="t('OUTSIDER_VOICE.PANEL.RETURN.OPEN_DEAL')"
              @click="openDeal(call.opportunity_id)"
            />
            <CallButton
              :number="call.customer_number"
              :label="t('OUTSIDER_VOICE.PANEL.RETURN.CALL_BACK')"
            />
          </span>
        </div>
      </section>

      <!-- histórico -->
      <section
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-n-weak"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PANEL.HISTORY.TITLE') }}
          </h3>
          <span class="flex flex-wrap items-center gap-2">
            <Select v-model="filters.direction" :options="directionOptions" />
            <Select v-model="filters.status" :options="statusOptions" />
            <Select
              v-if="stats.manager"
              v-model="filters.user_id"
              :options="sellerOptions"
            />
          </span>
        </div>
        <p v-if="!calls.length" class="px-4 py-3 mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.PANEL.HISTORY.EMPTY') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm min-w-[46rem]">
            <thead>
              <tr class="text-xs text-left text-n-slate-11">
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.WHEN') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.CUSTOMER') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.SELLER') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.SITUATION') }}
                </th>
                <th class="px-4 py-2 font-medium text-right">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.DURATION') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="call in calls"
                :key="call.id"
                class="border-t border-n-weak"
                data-testid="calls-history-row"
              >
                <td class="px-4 py-2.5 whitespace-nowrap text-n-slate-11">
                  <span class="flex items-center gap-2">
                    <Icon
                      :icon="
                        call.direction === 'inbound'
                          ? 'i-lucide-phone-incoming'
                          : 'i-lucide-phone-outgoing'
                      "
                      class="size-3.5"
                      :title="
                        t(
                          `OUTSIDER_VOICE.PANEL.HISTORY.DIRECTIONS.${call.direction}`
                        )
                      "
                    />
                    {{ formatDateTime(call.started_at, t) }}
                  </span>
                </td>
                <td class="px-4 py-2.5">
                  <span class="flex items-center gap-2 min-w-0">
                    <span class="truncate text-n-slate-12">
                      {{ customerName(call) }}
                    </span>
                    <button
                      v-if="call.opportunity_id"
                      type="button"
                      class="shrink-0 text-n-slate-11 hover:text-n-slate-12"
                      :title="t('OUTSIDER_VOICE.PANEL.RETURN.OPEN_DEAL')"
                      @click="openDeal(call.opportunity_id)"
                    >
                      <Icon icon="i-lucide-kanban" class="size-3.5" />
                    </button>
                    <CallButton show-number :number="call.customer_number" />
                  </span>
                </td>
                <td class="px-4 py-2.5 text-n-slate-12">
                  {{
                    call.user?.name || t('OUTSIDER_VOICE.PANEL.HISTORY.NOBODY')
                  }}
                </td>
                <td class="px-4 py-2.5">
                  <span
                    class="px-2 py-0.5 text-xs rounded-md whitespace-nowrap"
                    :class="STATUS_COLORS[call.status]"
                  >
                    {{
                      t(`OUTSIDER_VOICE.PANEL.HISTORY.STATUS.${call.status}`)
                    }}
                  </span>
                  <span
                    v-if="call.returned_by"
                    class="block mt-0.5 text-xs text-n-slate-11"
                  >
                    {{
                      t('OUTSIDER_VOICE.PANEL.HISTORY.RETURNED_BY', {
                        name: call.returned_by.name,
                      })
                    }}
                  </span>
                </td>
                <td class="px-4 py-2.5 text-right tabular-nums text-n-slate-12">
                  {{
                    call.talk_seconds ? formatDuration(call.talk_seconds) : '—'
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div
          v-if="calls.length < total"
          class="px-4 py-2 border-t border-n-weak"
        >
          <Button
            size="sm"
            variant="ghost"
            :label="t('OUTSIDER_VOICE.PANEL.HISTORY.LOAD_MORE')"
            :is-loading="isLoadingMore"
            @click="loadMore"
          />
        </div>
      </section>
    </template>
  </div>
</template>
