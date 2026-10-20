<script setup>
// OUTSIDER: funil de um pipeline, uma linha por etapa aberta e a linha final de ganhos.
// "Passaram" (com barra) e "Conversão" contam os negócios criados no período; "Agora" e
// "Ponderado" são o retrato do Kanban; "Tempo médio" usa as saídas da etapa no período e
// "Parados há" a média dos abertos na etapa hoje.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatMoney } from '../../helpers';

const props = defineProps({
  funnel: { type: Object, required: true },
});

const { t } = useI18n();

const max = computed(() =>
  Math.max(1, ...props.funnel.stages.map(stage => stage.reached_count))
);

const percent = value =>
  value === null || value === undefined
    ? '—'
    : `${String(value).replace('.', ',')}%`;

const days = value =>
  value === null || value === undefined
    ? '—'
    : t('OUTSIDER_CRM.REPORTS.DAYS', { days: String(value).replace('.', ',') });

const width = count => `${(count * 100) / max.value}%`;

const previousReached = index =>
  index === 0 ? null : props.funnel.stages[index - 1].reached_count;

const lastReached = computed(
  () => props.funnel.stages.at(-1)?.reached_count ?? 0
);

const totals = computed(() =>
  props.funnel.stages.reduce(
    (sum, stage) => ({
      count: sum.count + stage.open_count,
      value: sum.value + stage.open_value_cents,
      weighted: sum.weighted + stage.weighted_value_cents,
    }),
    { count: 0, value: 0, weighted: 0 }
  )
);
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full text-sm min-w-[46rem]">
      <thead>
        <tr class="text-xs text-left text-n-slate-11">
          <th class="py-2 pr-3 font-normal">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.STAGE') }}
          </th>
          <th class="w-[28%] py-2 pr-3 font-normal">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.REACHED') }}
          </th>
          <th class="py-2 pr-3 font-normal text-right">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.CONVERSION') }}
          </th>
          <th class="py-2 pr-3 font-normal text-right">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.NOW') }}
          </th>
          <th class="py-2 pr-3 font-normal text-right">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.WEIGHTED') }}
          </th>
          <th class="py-2 pr-3 font-normal text-right">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.AVERAGE_DAYS') }}
          </th>
          <th class="py-2 font-normal text-right">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.CURRENT_DAYS') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="(stage, index) in funnel.stages"
          :key="stage.id"
          class="border-t border-n-weak text-n-slate-12"
        >
          <td class="py-2 pr-3">
            <span class="flex items-center gap-2">
              <span
                class="rounded-full size-2 shrink-0"
                :style="{ background: stage.color || 'currentColor' }"
              />
              <span class="truncate">{{ stage.name }}</span>
            </span>
          </td>
          <td class="py-2 pr-3">
            <div
              v-tooltip="
                t('OUTSIDER_CRM.REPORTS.FUNNEL.REACHED_TOOLTIP', {
                  count: stage.reached_count,
                  total: funnel.cohort_count,
                })
              "
              class="flex items-center gap-2"
            >
              <div class="flex-1 h-2 rounded bg-n-alpha-2">
                <div
                  class="h-2 rounded bg-n-blue-9"
                  :style="{ width: width(stage.reached_count) }"
                />
              </div>
              <span class="w-8 text-right tabular-nums">
                {{ stage.reached_count }}
              </span>
            </div>
          </td>
          <td
            v-tooltip="
              index > 0
                ? t('OUTSIDER_CRM.REPORTS.FUNNEL.CONVERSION_TOOLTIP', {
                    count: stage.reached_count,
                    previous: previousReached(index),
                  })
                : ''
            "
            class="py-2 pr-3 text-right tabular-nums"
          >
            {{ percent(stage.conversion_rate) }}
          </td>
          <td class="py-2 pr-3 text-right tabular-nums">
            {{
              t('OUTSIDER_CRM.REPORTS.COUNT_VALUE', {
                count: stage.open_count,
                value: formatMoney(stage.open_value_cents),
              })
            }}
          </td>
          <td class="py-2 pr-3 text-right tabular-nums">
            {{ formatMoney(stage.weighted_value_cents) }}
          </td>
          <td
            v-tooltip="
              t('OUTSIDER_CRM.REPORTS.FUNNEL.EXITS', {
                count: stage.exits_count,
              })
            "
            class="py-2 pr-3 text-right tabular-nums"
          >
            {{ days(stage.average_days) }}
          </td>
          <td class="py-2 text-right tabular-nums">
            <span
              :class="{
                'text-n-amber-11':
                  stage.sla_hours &&
                  stage.current_average_days * 24 > stage.sla_hours,
              }"
            >
              {{ days(stage.current_average_days) }}
            </span>
          </td>
        </tr>
        <tr class="font-medium border-t border-n-weak text-n-slate-12">
          <td class="py-2 pr-3">
            <span class="flex items-center gap-2">
              <span class="i-lucide-trophy size-3.5 text-n-teal-11" />
              {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.WON') }}
            </span>
          </td>
          <td class="py-2 pr-3">
            <div class="flex items-center gap-2">
              <div class="flex-1 h-2 rounded bg-n-alpha-2">
                <div
                  class="h-2 rounded bg-n-blue-9"
                  :style="{ width: width(funnel.won.count) }"
                />
              </div>
              <span class="w-8 text-right tabular-nums">
                {{ funnel.won.count }}
              </span>
            </div>
          </td>
          <td
            v-tooltip="
              t('OUTSIDER_CRM.REPORTS.FUNNEL.CONVERSION_TOOLTIP', {
                count: funnel.won.count,
                previous: lastReached,
              })
            "
            class="py-2 pr-3 text-right tabular-nums"
          >
            {{ percent(funnel.won.conversion_rate) }}
          </td>
          <td colspan="4" />
        </tr>
      </tbody>
      <tfoot>
        <tr class="border-t border-n-weak text-n-slate-11">
          <td colspan="3" class="py-2 pr-3 text-xs">
            {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.TOTAL_OPEN') }}
          </td>
          <td class="py-2 pr-3 text-right tabular-nums text-n-slate-12">
            {{
              t('OUTSIDER_CRM.REPORTS.COUNT_VALUE', {
                count: totals.count,
                value: formatMoney(totals.value),
              })
            }}
          </td>
          <td class="py-2 pr-3 text-right tabular-nums text-n-slate-12">
            {{ formatMoney(totals.weighted) }}
          </td>
          <td colspan="2" />
        </tr>
      </tfoot>
    </table>
  </div>
</template>
