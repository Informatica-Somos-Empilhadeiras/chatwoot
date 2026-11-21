<script setup>
// OUTSIDER: o que ficou fora do relatório dos técnicos: pedidos faturados no período sem técnico informado (com o link
// para informar no pedido) e pedidos com técnico informado que ainda não têm nota válida (entram quando faturarem).
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatMoney, formatDate, companyName } from '../../erp/erpStore';
import { saleLink, notesText } from './reportHelpers';

defineProps({
  data: { type: Object, required: true },
  accountId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const label = (key, values) =>
  t(`OUTSIDER_REPORTS.TECHNICIANS.${key}`, values || {});

const TH =
  'px-3 py-2 text-[11px] font-medium tracking-wide text-left uppercase text-n-slate-10 whitespace-nowrap';
const TD = 'px-3 py-2 align-middle';
</script>

<template>
  <div class="grid gap-5 2xl:grid-cols-2">
    <section
      id="sem-tecnico"
      class="overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
    >
      <header class="flex flex-col gap-0.5 px-4 py-3 border-b border-n-weak">
        <h2
          class="flex items-center gap-1.5 mb-0 text-sm font-medium text-n-slate-12"
        >
          <Icon icon="i-lucide-triangle-alert" class="size-4 text-n-amber-11" />
          {{ label('LISTS.WITHOUT_TECH') }}
        </h2>
        <span class="text-xs text-n-slate-10">
          {{ label('LISTS.WITHOUT_TECH_HINT') }}
        </span>
      </header>
      <p
        v-if="!data.sem_tecnico.length"
        class="p-5 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ label('LISTS.WITHOUT_TECH_EMPTY') }}
      </p>
      <div v-else class="overflow-x-auto max-h-[28rem]">
        <table class="w-full text-sm">
          <thead class="sticky top-0 border-b border-n-weak bg-n-solid-1">
            <tr>
              <th :class="TH">{{ label('DETAIL.ORDER') }}</th>
              <th :class="TH">{{ label('DETAIL.NOTES') }}</th>
              <th :class="TH">{{ label('DETAIL.CLIENT') }}</th>
              <th :class="TH">{{ label('DETAIL.SELLER') }}</th>
              <th :class="TH" class="text-right">
                {{ label('DETAIL.VALUE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="sale in data.sem_tecnico"
              :key="`${sale.unidade}:${sale.pedido}`"
              class="border-b last:border-b-0 border-n-weak"
            >
              <td :class="TD" class="whitespace-nowrap">
                <router-link
                  :to="saleLink(accountId, sale)"
                  class="inline-flex items-center gap-1 font-medium text-n-blue-11 hover:underline"
                >
                  {{ label('DETAIL.ORDER_NUMBER', { number: sale.pedido }) }}
                  <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
                </router-link>
                <span class="block text-[11px] text-n-slate-10">
                  {{ companyName(sale.unidade) }}
                </span>
              </td>
              <td :class="TD" class="text-xs whitespace-nowrap text-n-slate-11">
                {{ notesText(sale) }}
                <span class="block">{{ formatDate(sale.data_nota) }}</span>
              </td>
              <td :class="TD" class="text-n-slate-12">{{ sale.cliente }}</td>
              <td :class="TD" class="text-n-slate-11">{{ sale.vendedor }}</td>
              <td :class="TD" class="text-right tabular-nums whitespace-nowrap">
                {{ formatMoney(sale.total) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section
      id="aguardando"
      class="overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
    >
      <header class="flex flex-col gap-0.5 px-4 py-3 border-b border-n-weak">
        <h2
          class="flex items-center gap-1.5 mb-0 text-sm font-medium text-n-slate-12"
        >
          <Icon icon="i-lucide-hourglass" class="size-4 text-n-slate-10" />
          {{ label('LISTS.WAITING') }}
        </h2>
        <span class="text-xs text-n-slate-10">
          {{ label('LISTS.WAITING_HINT') }}
        </span>
      </header>
      <p
        v-if="!data.aguardando.length"
        class="p-5 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ label('LISTS.WAITING_EMPTY') }}
      </p>
      <div v-else class="overflow-x-auto max-h-[28rem]">
        <table class="w-full text-sm">
          <thead class="sticky top-0 border-b border-n-weak bg-n-solid-1">
            <tr>
              <th :class="TH">{{ label('DETAIL.ORDER') }}</th>
              <th :class="TH">{{ label('TABLE.TECH') }}</th>
              <th :class="TH">{{ label('DETAIL.CLIENT') }}</th>
              <th :class="TH" class="text-right">
                {{ label('DETAIL.VALUE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="sale in data.aguardando"
              :key="`${sale.unidade}:${sale.pedido}`"
              class="border-b last:border-b-0 border-n-weak"
            >
              <td :class="TD" class="whitespace-nowrap">
                <router-link
                  :to="saleLink(accountId, sale)"
                  class="font-medium text-n-blue-11 hover:underline"
                >
                  {{ label('DETAIL.ORDER_NUMBER', { number: sale.pedido }) }}
                </router-link>
                <span class="block text-[11px] text-n-slate-10">
                  {{ companyName(sale.unidade) }}
                </span>
              </td>
              <td :class="TD" class="text-n-slate-12">
                {{ sale.linhas.map(line => line.tecnico).join(', ') }}
              </td>
              <td :class="TD" class="text-n-slate-11">{{ sale.cliente }}</td>
              <td :class="TD" class="text-right tabular-nums whitespace-nowrap">
                {{ formatMoney(sale.total) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
