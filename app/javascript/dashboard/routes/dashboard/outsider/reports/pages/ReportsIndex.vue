<script setup>
// OUTSIDER: página da seção Relatórios de gestão. A aba vem da rota (gestao/:report); cada relatório é um componente
// próprio (reportsCatalog.js), assim os próximos entram sem mexer aqui.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { openReports, REPORTS_ROUTE } from '../reportsCatalog';
import { erpState } from '../../erp/erpStore';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const reports = computed(() => (erpState.loaded ? openReports() : []));
const current = computed(
  () =>
    reports.value.find(report => report.key === route.params.report) ||
    reports.value[0]
);

const go = key => {
  if (key === current.value?.key) return;
  router.push({
    name: REPORTS_ROUTE,
    params: { ...route.params, report: key },
  });
};
</script>

<template>
  <section class="flex w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex flex-col w-full h-full min-w-0">
      <header class="px-4 shrink-0 sm:px-6">
        <div
          class="flex flex-wrap items-end justify-between gap-3 pt-5 pb-4 mx-auto max-w-[110rem]"
        >
          <div class="flex flex-col gap-0.5 min-w-0">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('OUTSIDER_REPORTS.SIDEBAR') }}
            </span>
            <h1 class="mb-0 text-xl font-medium text-n-slate-12">
              {{ current ? t(current.label) : t('OUTSIDER_REPORTS.SIDEBAR') }}
            </h1>
          </div>
          <nav
            v-if="reports.length > 1"
            class="flex items-center gap-0.5 p-0.5 overflow-x-auto rounded-lg bg-n-alpha-2"
          >
            <button
              v-for="report in reports"
              :key="report.key"
              type="button"
              class="flex items-center gap-1.5 h-8 px-3 text-[13px] rounded-md whitespace-nowrap"
              :class="
                current?.key === report.key
                  ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="go(report.key)"
            >
              <Icon :icon="report.icon" class="size-4" />
              {{ t(report.label) }}
            </button>
          </nav>
        </div>
      </header>
      <main class="flex-1 min-h-0 px-4 overflow-y-auto sm:px-6">
        <div class="w-full pb-8 mx-auto max-w-[110rem]">
          <component
            :is="current.component"
            v-if="current"
            :key="current.key"
          />
          <div
            v-else-if="erpState.loaded"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
          >
            <Icon
              icon="i-lucide-chart-column-big"
              class="size-10 text-n-slate-9"
            />
            <p class="max-w-md mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_REPORTS.NONE') }}
            </p>
          </div>
        </div>
      </main>
    </div>
  </section>
</template>
