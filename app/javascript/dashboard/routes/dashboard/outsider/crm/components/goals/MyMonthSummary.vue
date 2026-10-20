<script setup>
// OUTSIDER: resumo do mês da própria pessoa na tela principal do CRM (só texto): vendido, quanto da
// meta já atingiu, quanto falta e a comissão. O detalhe, negócio a negócio, fica na seção Metas.
// Some para quem não vende nem tem meta (GET /performance?only=me devolve "me" vazio).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  attainment,
  currentMonth,
  formatMoney,
  formatMonth,
} from '../../helpers';

const props = defineProps({
  refreshKey: { type: Number, default: 0 },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const me = ref(null);
const month = ref(currentMonth());

const percent = computed(() =>
  attainment(me.value?.won_cents, me.value?.goal_cents)
);

const missingLabel = missing => {
  if (missing === null) return '—';
  return missing ? formatMoney(missing) : t('OUTSIDER_CRM.MY_MONTH.REACHED');
};

const items = computed(() => {
  if (!me.value) return [];
  const goal = me.value.goal_cents;
  const missing = goal ? Math.max(goal - me.value.won_cents, 0) : null;
  return [
    {
      key: 'SOLD',
      value: formatMoney(me.value.won_cents),
      hint: t('OUTSIDER_CRM.GOALS.DEALS', me.value.won_count),
    },
    {
      key: 'GOAL',
      value: goal ? `${percent.value}%` : t('OUTSIDER_CRM.GOALS.NO_GOAL'),
      hint: goal
        ? t('OUTSIDER_CRM.MY_MONTH.OF_GOAL', { goal: formatMoney(goal) })
        : '',
      reached: percent.value !== null && percent.value >= 100,
    },
    {
      key: 'MISSING',
      value: missingLabel(missing),
      reached: missing === 0,
    },
    {
      key: 'COMMISSION',
      value: formatMoney(me.value.commission_cents),
      commission: true,
    },
  ];
});

const load = async () => {
  month.value = currentMonth();
  try {
    const { data } = await CrmAPI.getPerformance(month.value, 'me');
    me.value = data.me;
  } catch {
    // o resumo é um extra: se falhar, a tela segue sem ele
    me.value = null;
  }
};

const openGoals = () =>
  router.push({ params: { ...route.params, tab: 'goals' }, query: {} });

watch(() => props.refreshKey, load, { immediate: true });
</script>

<template>
  <section
    v-if="me"
    class="flex flex-wrap items-center gap-x-6 gap-y-2 px-4 py-2.5 rounded-xl bg-n-alpha-1"
  >
    <span class="flex items-center gap-2 text-sm font-medium text-n-slate-12">
      <Icon icon="i-lucide-target" class="size-4 text-n-slate-11" />
      <span class="inline-block first-letter:uppercase">
        {{ t('OUTSIDER_CRM.MY_MONTH.TITLE', { month: formatMonth(month) }) }}
      </span>
    </span>
    <div
      v-for="item in items"
      :key="item.key"
      class="flex items-baseline gap-1.5 min-w-0"
    >
      <span class="text-xs text-n-slate-11">
        {{ t(`OUTSIDER_CRM.MY_MONTH.${item.key}`) }}
      </span>
      <span
        class="text-sm font-semibold"
        :class="
          item.commission || item.reached ? 'text-n-teal-11' : 'text-n-slate-12'
        "
      >
        {{ item.value }}
      </span>
      <span v-if="item.hint" class="text-xs text-n-slate-10">
        {{ item.hint }}
      </span>
    </div>
    <div class="flex-1" />
    <Button
      size="xs"
      variant="link"
      :label="t('OUTSIDER_CRM.MY_MONTH.DETAILS')"
      @click="openGoals"
    />
  </section>
</template>
