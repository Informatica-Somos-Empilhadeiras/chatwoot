<script setup>
// OUTSIDER: aba Metas do CRM (GET /outsider/crm/performance). No mês escolhido: o vendedor vê a
// própria meta, o vendido e a comissão, negócio por negócio; gestor e administrador veem também as
// unidades e os vendedores que acompanham. Comissão = valor ganho no mês × percentual.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import CrmAPI from 'dashboard/api/outsider/crm';
import { useCrmChanges } from '../../live';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import LoadError from '../../activity/LoadError.vue';
import GoalProgress from './GoalProgress.vue';
import {
  currentMonth,
  errorMessage,
  formatDate,
  formatMoney,
  formatMonth,
  formatPercent,
  shiftMonth,
} from '../../helpers';

defineProps({
  access: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const month = ref(currentMonth());
const data = ref(null);
const isLoading = ref(false);
const loadError = ref('');

const isFuture = computed(() => month.value > currentMonth());
const me = computed(() => data.value?.me);
const hasGoals = computed(
  () =>
    data.value &&
    (data.value.me?.goal_cents ||
      data.value.units.some(unit => unit.goal_cents) ||
      data.value.sellers.some(seller => seller.goal_cents))
);

// options.silent: recarga ao vivo, sem o indicador de carregando
const load = async options => {
  if (!options?.silent) isLoading.value = true;
  try {
    const response = await CrmAPI.getPerformance(month.value);
    data.value = response.data;
    loadError.value = '';
  } catch (error) {
    loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
  }
};

const openSettings = section =>
  router.replace({
    params: { ...route.params, tab: 'settings' },
    query: { secao: section },
  });

watch(month, () => load());
onMounted(load);

// negócio ganho, valor ou responsável mudou, ou as metas e a comissão: os números mudam na hora
useCrmChanges(changes => {
  if (changes.some(change => change.kind !== 'task')) load({ silent: true });
});
</script>

<template>
  <div class="flex flex-col gap-5">
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
        class="px-1 text-base font-medium inline-block first-letter:uppercase text-n-slate-12"
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
      <Button
        v-if="month !== currentMonth()"
        size="sm"
        variant="ghost"
        :label="t('OUTSIDER_CRM.GOALS.THIS_MONTH')"
        @click="month = currentMonth()"
      />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <div class="flex-1" />
      <template v-if="access.administrator">
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-target"
          :label="t('OUTSIDER_CRM.GOALS.SET_GOALS')"
          @click="openSettings('goals')"
        />
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-percent"
          :label="t('OUTSIDER_CRM.GOALS.SET_COMMISSION')"
          @click="openSettings('commission')"
        />
      </template>
    </div>

    <LoadError v-if="loadError" :message="loadError" @retry="load" />

    <div
      v-else-if="!data && isLoading"
      class="flex justify-center p-8 text-n-slate-10"
    >
      <Spinner />
    </div>

    <template v-else-if="data">
      <p
        v-if="!hasGoals"
        class="p-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
      >
        {{
          access.administrator
            ? t('OUTSIDER_CRM.GOALS.EMPTY_ADMIN')
            : t('OUTSIDER_CRM.GOALS.EMPTY')
        }}
      </p>

      <section
        v-if="me"
        class="flex flex-col gap-4 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.GOALS.MINE') }}
        </span>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div class="flex flex-col gap-0.5">
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.SOLD') }}
            </span>
            <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
              {{ formatMoney(me.won_cents) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.DEALS', me.won_count) }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5">
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.GOAL') }}
            </span>
            <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
              {{ me.goal_cents ? formatMoney(me.goal_cents) : '—' }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5">
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.COMMISSION') }}
            </span>
            <span class="text-2xl font-semibold tabular-nums text-n-teal-11">
              {{ formatMoney(me.commission_cents) }}
            </span>
            <span v-if="isFuture" class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.FUTURE') }}
            </span>
          </div>
        </div>
        <GoalProgress large :won="me.won_cents" :goal="me.goal_cents" />

        <div class="flex flex-col gap-2">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('OUTSIDER_CRM.GOALS.HOW_COMMISSION') }}
          </span>
          <p
            v-if="!me.deals.length"
            class="p-3 mb-0 text-sm rounded-lg bg-n-alpha-1 text-n-slate-11"
          >
            {{ t('OUTSIDER_CRM.GOALS.NO_DEALS') }}
          </p>
          <div v-else class="overflow-x-auto rounded-lg bg-n-alpha-1">
            <table class="w-full text-sm min-w-[36rem]">
              <thead>
                <tr class="text-xs text-left text-n-slate-11">
                  <th class="px-3 py-2 font-medium">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.DEAL') }}
                  </th>
                  <th class="px-3 py-2 font-medium">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.WON_AT') }}
                  </th>
                  <th class="px-3 py-2 font-medium text-right">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.VALUE') }}
                  </th>
                  <th class="px-3 py-2 font-medium text-right">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.PERCENT') }}
                  </th>
                  <th class="px-3 py-2 font-medium text-right">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.COMMISSION') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="deal in me.deals"
                  :key="deal.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2">
                    <span class="block font-medium text-n-slate-12">
                      {{ deal.title }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{ deal.code }} · {{ deal.business_unit_name }} ·
                      {{ deal.contact_name }}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-n-slate-11">
                    {{ formatDate(deal.closed_at.slice(0, 10)) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-12">
                    {{ formatMoney(deal.value_cents) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ formatPercent(deal.bp) }}
                  </td>
                  <td
                    class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
                  >
                    {{ formatMoney(deal.commission_cents) }}
                  </td>
                </tr>
                <tr class="border-t border-n-weak">
                  <td class="px-3 py-2 font-medium text-n-slate-12" colspan="2">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.TOTAL') }}
                  </td>
                  <td
                    class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
                  >
                    {{ formatMoney(me.won_cents) }}
                  </td>
                  <td />
                  <td
                    class="px-3 py-2 font-semibold text-right tabular-nums text-n-teal-11"
                  >
                    {{ formatMoney(me.commission_cents) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.GOALS.FORMULA') }}
          </p>
        </div>
      </section>

      <template v-if="data.manager">
        <section
          v-if="data.totals"
          class="grid grid-cols-1 gap-4 p-4 rounded-xl sm:grid-cols-3 bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <div class="flex flex-col gap-0.5">
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.TEAM_SOLD') }}
            </span>
            <span class="text-xl font-semibold tabular-nums text-n-slate-12">
              {{ formatMoney(data.totals.won_cents) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.DEALS', data.totals.won_count) }}
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.TEAM_GOAL') }}
            </span>
            <span class="text-xl font-semibold tabular-nums text-n-slate-12">
              {{
                data.totals.goal_cents
                  ? formatMoney(data.totals.goal_cents)
                  : '—'
              }}
            </span>
            <GoalProgress
              :won="data.totals.won_cents"
              :goal="data.totals.goal_cents"
            />
          </div>
          <div class="flex flex-col gap-0.5">
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.GOALS.TEAM_COMMISSION') }}
            </span>
            <span class="text-xl font-semibold tabular-nums text-n-teal-11">
              {{ formatMoney(data.totals.commission_cents) }}
            </span>
          </div>
        </section>

        <section v-if="data.units.length" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.GOALS.UNITS') }}
          </span>
          <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
            <div
              v-for="unit in data.units"
              :key="unit.id"
              class="flex flex-col gap-2 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
            >
              <div class="flex items-baseline justify-between gap-2">
                <span class="font-medium truncate text-n-slate-12">
                  {{ unit.name }}
                </span>
                <span class="text-xs shrink-0 text-n-slate-11">
                  {{ t('OUTSIDER_CRM.GOALS.DEALS', unit.won_count) }}
                </span>
              </div>
              <span class="text-sm tabular-nums text-n-slate-12">
                {{
                  unit.goal_cents
                    ? t('OUTSIDER_CRM.GOALS.OF', {
                        won: formatMoney(unit.won_cents),
                        goal: formatMoney(unit.goal_cents),
                      })
                    : formatMoney(unit.won_cents)
                }}
              </span>
              <GoalProgress :won="unit.won_cents" :goal="unit.goal_cents" />
            </div>
          </div>
        </section>

        <section v-if="data.sellers.length" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.GOALS.SELLERS') }}
          </span>
          <div
            class="overflow-x-auto rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
          >
            <table class="w-full text-sm min-w-[40rem]">
              <thead>
                <tr class="text-xs text-left text-n-slate-11">
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.SELLER') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium text-right">
                    {{ t('OUTSIDER_CRM.GOALS.SOLD') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium text-right">
                    {{ t('OUTSIDER_CRM.GOALS.GOAL') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium w-56">
                    {{ t('OUTSIDER_CRM.GOALS.TABLE.PROGRESS') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium text-right">
                    {{ t('OUTSIDER_CRM.GOALS.COMMISSION') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="seller in data.sellers"
                  :key="seller.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-4 py-3">
                    <span class="flex items-center gap-2 min-w-0">
                      <Avatar
                        :name="seller.name"
                        :src="seller.thumbnail"
                        :size="24"
                        rounded-full
                      />
                      <span class="truncate text-n-slate-12">
                        {{ seller.name }}
                      </span>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right tabular-nums">
                    <span class="block text-n-slate-12">
                      {{ formatMoney(seller.won_cents) }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{ t('OUTSIDER_CRM.GOALS.DEALS', seller.won_count) }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right tabular-nums text-n-slate-11">
                    {{
                      seller.goal_cents ? formatMoney(seller.goal_cents) : '—'
                    }}
                  </td>
                  <td class="px-4 py-3">
                    <GoalProgress
                      :won="seller.won_cents"
                      :goal="seller.goal_cents"
                    />
                  </td>
                  <td
                    class="px-4 py-3 font-medium text-right tabular-nums text-n-slate-12"
                  >
                    {{ formatMoney(seller.commission_cents) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.GOALS.SELLERS_HELP') }}
          </p>
        </section>
      </template>
    </template>
  </div>
</template>
