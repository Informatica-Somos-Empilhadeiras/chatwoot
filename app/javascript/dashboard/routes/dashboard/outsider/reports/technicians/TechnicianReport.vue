<script setup>
// OUTSIDER: relatório de desempenho dos técnicos (Outsider::Erp::TechnicianReport). Só pedidos de venda FATURADOS no
// período (nota de saída válida emitida entre as datas); o técnico é o informado pelo vendedor no pedido (ErpSaleAttribution).
// Números do período no topo, uma linha por técnico (clique abre os pedidos dele) e, embaixo, o que ficou de fora:
// pedidos faturados sem técnico e pedidos com técnico ainda sem nota. Exporta o detalhe em CSV. Pedido, OS e nota abrem
// o painel de detalhe da seção ERP por cima do relatório (sem sair da página); OS de garantia, entrega técnica e frotas
// (Configurações) aparecem marcadas e não somam para o técnico.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/outsider/reports';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TechnicianReportLists from './TechnicianReportLists.vue';
import TechnicianReportSettings from './TechnicianReportSettings.vue';
import ErpRecordPanel from '../../erp/records/ErpRecordPanel.vue';
import {
  erpState,
  erpErrorMessage,
  formatMoney,
  formatDate,
  companyName,
} from '../../erp/erpStore';
import { formatNumber } from '../../erp/budgets/budgetHelpers';
import { PERIODS, periodRange, detailCsv, download } from './reportHelpers';

const { t } = useI18n();
const label = (key, values) =>
  t(`OUTSIDER_REPORTS.TECHNICIANS.${key}`, values || {});

const period = ref('month');
const from = ref(periodRange('month').from);
const to = ref(periodRange('month').to);
const units = ref([]);
const data = ref(null);
const loading = ref(false);
const failure = ref('');
const expanded = ref('');
const settingsRef = ref(null);
let lastRun = 0;

const load = async () => {
  if (!from.value || !to.value) return;
  lastRun += 1;
  const mine = lastRun;
  loading.value = true;
  failure.value = '';
  try {
    const { data: result } = await ReportsAPI.technicians({
      from: from.value,
      to: to.value,
      companies: units.value,
    });
    if (mine === lastRun) data.value = result;
  } catch (error) {
    if (mine === lastRun) failure.value = erpErrorMessage(t, error);
  } finally {
    if (mine === lastRun) loading.value = false;
  }
};

watch(period, value => {
  if (value === 'custom') return;
  ({ from: from.value, to: to.value } = periodRange(value));
});
watch([from, to, units], load, { immediate: true, deep: true });

const toggleUnit = unit => {
  units.value = units.value.includes(unit)
    ? units.value.filter(item => item !== unit)
    : [...units.value, unit];
};

const summary = computed(() => data.value?.resumo || {});
const technicians = computed(() => data.value?.tecnicos || []);
const maxShare = computed(() =>
  Math.max(...technicians.value.map(row => row.participacao_pct), 1)
);

const salesOf = name =>
  (data.value?.pedidos || [])
    .filter(sale => sale.linhas.some(line => line.tecnico === name))
    .map(sale => ({
      ...sale,
      linha: sale.linhas.find(line => line.tecnico === name),
    }));

// o registro aberto no painel da direita: pedido (técnico e OS informados nele), OS ou nota
const opened = ref(null);
const openRecord = (kind, company, number) => {
  if (!company || !Number(number)) return;
  opened.value = { kind, company, number: Number(number) };
};

const excludedTypes = computed(() =>
  (summary.value.fora_da_soma_tipos || [])
    .map(type => type.charAt(0) + type.slice(1).toLowerCase())
    .join(', ')
);

const toggle = name => {
  expanded.value = expanded.value === name ? '' : name;
};

const exportCsv = () => {
  const headers = [
    'TECNICO',
    'UNIDADE',
    'PEDIDO',
    'NOTAS',
    'DATA_NOTA',
    'CLIENTE',
    'VENDEDOR',
    'ATENDIMENTO',
    'OS',
    'FORA_DA_SOMA',
    'PARTE',
    'VALOR',
    'PECAS',
    'SERVICOS',
  ].map(key => label(`CSV.${key}`));
  download(
    detailCsv(data.value?.pedidos || [], headers),
    `desempenho-tecnicos-${from.value}-a-${to.value}.csv`
  );
};

const percent = value => `${formatNumber(value, 1)}%`;

const INPUT =
  '!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
const TH =
  'px-3 py-2 text-[11px] font-medium tracking-wide text-left uppercase text-n-slate-10 whitespace-nowrap';
const TD = 'px-3 py-2.5 align-middle whitespace-nowrap tabular-nums';
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      class="flex flex-wrap items-center gap-2 p-3 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center p-0.5 rounded-lg bg-n-alpha-2">
        <button
          v-for="item in PERIODS"
          :key="item"
          type="button"
          class="h-7 px-2.5 text-xs rounded-md whitespace-nowrap"
          :class="
            period === item
              ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="period = item"
        >
          {{ label(`PERIODS.${item.toUpperCase()}`) }}
        </button>
      </div>
      <template v-if="period === 'custom'">
        <input
          v-model="from"
          type="date"
          :class="INPUT"
          :aria-label="label('FROM')"
        />
        <span class="text-xs text-n-slate-10">{{ label('TO') }}</span>
        <input
          v-model="to"
          type="date"
          :class="INPUT"
          :aria-label="label('UNTIL')"
        />
      </template>
      <span v-else class="text-xs text-n-slate-10 tabular-nums">
        {{ formatDate(from) }} – {{ formatDate(to) }}
      </span>
      <span class="w-px h-5 mx-1 bg-n-weak" />
      <div class="flex flex-wrap items-center gap-1">
        <button
          v-for="unit in erpState.companies"
          :key="unit"
          type="button"
          class="h-7 px-2.5 text-xs rounded-md"
          :class="
            units.includes(unit)
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
          "
          :title="unit"
          @click="toggleUnit(unit)"
        >
          {{ companyName(unit) }}
        </button>
        <span v-if="!units.length" class="text-xs text-n-slate-10">
          {{ label('ALL_UNITS') }}
        </span>
      </div>
      <span class="flex-1" />
      <Spinner v-if="loading && data" class="size-4 text-n-slate-10" />
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-download"
        :label="label('EXPORT')"
        :disabled="!data?.pedidos?.length"
        @click="exportCsv"
      />
      <Button
        v-if="data?.pode_configurar"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-settings-2"
        :label="label('SETTINGS')"
        @click="settingsRef?.open(data)"
      />
    </div>

    <p
      class="flex items-start gap-2 px-3 py-2 mb-0 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-info" class="mt-0.5 size-3.5 shrink-0" />
      {{ label('RULE') }}
    </p>

    <div v-if="loading && !data" class="flex justify-center p-10">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else-if="failure && !data"
      class="flex flex-col items-center gap-3 p-8 text-center rounded-xl bg-n-alpha-1"
    >
      <p class="mb-0 text-sm text-n-ruby-11">{{ failure }}</p>
      <Button
        size="sm"
        variant="faded"
        color="slate"
        :label="t('OUTSIDER_ERP.CONTACT.RETRY')"
        @click="load"
      />
    </div>

    <template v-else-if="data">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <div
          class="flex flex-col gap-1 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">{{ label('KPI.BILLED') }}</span>
          <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(summary.faturado) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ label('KPI.ORDERS', { count: summary.pedidos }) }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">{{
            label('KPI.WITH_TECH')
          }}</span>
          <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(summary.faturado_com_tecnico) }}
          </span>
          <div class="flex items-center gap-2">
            <span
              class="flex-1 h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
            >
              <span
                class="block h-full rounded-full bg-n-brand"
                :style="{
                  width: `${Math.min(summary.cobertura_pct || 0, 100)}%`,
                }"
              />
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              {{
                label('KPI.COVERAGE', { pct: percent(summary.cobertura_pct) })
              }}
            </span>
          </div>
          <span class="text-[11px] text-n-slate-10">
            {{
              label('KPI.SOURCES', {
                erp: summary.pedidos_tecnico_erp || 0,
                chat:
                  (summary.pedidos_com_tecnico || 0) -
                  (summary.pedidos_tecnico_erp || 0),
              })
            }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">{{
            label('KPI.COMMISSION')
          }}</span>
          <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(summary.comissao) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              label('KPI.COMMISSION_HINT', {
                pct: percent(data.comissao_pct),
                count: summary.tecnicos,
              })
            }}
          </span>
        </div>
        <a
          href="#sem-tecnico"
          class="flex flex-col gap-1 p-4 border rounded-xl border-n-amber-6 bg-n-amber-2 hover:bg-n-amber-3"
        >
          <span class="flex items-center gap-1 text-xs text-n-amber-11">
            <Icon icon="i-lucide-triangle-alert" class="size-3.5" />
            {{ label('KPI.WITHOUT_TECH') }}
          </span>
          <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(summary.sem_tecnico_valor) }}
          </span>
          <span class="text-xs text-n-amber-11">
            {{
              label('KPI.WITHOUT_TECH_HINT', {
                count: summary.sem_tecnico_pedidos,
              })
            }}
          </span>
        </a>
        <a
          href="#aguardando"
          class="flex flex-col gap-1 p-4 border rounded-xl border-n-weak bg-n-solid-1 hover:bg-n-alpha-1"
        >
          <span class="flex items-center gap-1 text-xs text-n-slate-11">
            <Icon icon="i-lucide-hourglass" class="size-3.5" />
            {{ label('KPI.WAITING') }}
          </span>
          <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(summary.aguardando_valor) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              label('KPI.WAITING_HINT', { count: summary.aguardando_pedidos })
            }}
          </span>
        </a>
      </div>

      <p
        v-if="summary.fora_da_soma_pedidos"
        class="flex items-start gap-2 px-3 py-2 mb-0 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
        data-excluded-note
      >
        <Icon icon="i-lucide-circle-slash" class="mt-0.5 size-3.5 shrink-0" />
        {{
          label('EXCLUDED.NOTE', {
            value: formatMoney(summary.fora_da_soma_valor),
            count: summary.fora_da_soma_pedidos,
            types: excludedTypes,
          })
        }}
      </p>

      <section
        class="overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
      >
        <header class="px-4 py-3 border-b border-n-weak">
          <h2 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ label('TABLE.TITLE') }}
          </h2>
        </header>
        <p
          v-if="!technicians.length"
          class="p-6 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ label('TABLE.EMPTY') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="border-b border-n-weak">
              <tr>
                <th :class="TH">{{ label('TABLE.TECH') }}</th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.ORDERS') }}
                </th>
                <th :class="TH" class="text-right">{{ label('TABLE.OS') }}</th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.BILLED') }}
                </th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.PARTS') }}
                </th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.SERVICES') }}
                </th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.TICKET') }}
                </th>
                <th :class="TH">{{ label('TABLE.SHARE') }}</th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.LEAD') }}
                </th>
                <th :class="TH">{{ label('TABLE.GOAL') }}</th>
                <th :class="TH" class="text-right">
                  {{ label('TABLE.COMMISSION') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <template v-for="row in technicians" :key="row.tecnico">
                <tr
                  class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                  :class="expanded === row.tecnico && 'bg-n-alpha-1'"
                  @click="toggle(row.tecnico)"
                >
                  <td :class="TD">
                    <span class="flex items-center gap-2">
                      <Icon
                        :icon="
                          expanded === row.tecnico
                            ? 'i-lucide-chevron-down'
                            : 'i-lucide-chevron-right'
                        "
                        class="size-4 text-n-slate-10"
                      />
                      <span class="flex flex-col">
                        <span class="font-medium text-n-slate-12">
                          {{ row.tecnico }}
                        </span>
                        <span class="text-[11px] text-n-slate-10">
                          {{ row.unidades.map(companyName).join(', ') }}
                        </span>
                      </span>
                    </span>
                  </td>
                  <td :class="TD" class="text-right">{{ row.pedidos }}</td>
                  <td :class="TD" class="text-right">{{ row.os }}</td>
                  <td
                    :class="TD"
                    class="text-right font-medium text-n-slate-12"
                  >
                    {{ formatMoney(row.faturado) }}
                  </td>
                  <td :class="TD" class="text-right text-n-slate-11">
                    {{ formatMoney(row.pecas) }}
                  </td>
                  <td :class="TD" class="text-right text-n-slate-11">
                    {{ formatMoney(row.servicos) }}
                  </td>
                  <td :class="TD" class="text-right text-n-slate-11">
                    {{ formatMoney(row.ticket_medio) }}
                  </td>
                  <td :class="TD">
                    <span
                      class="flex items-center gap-2 min-w-[8rem]"
                      :title="percent(row.participacao_pct)"
                    >
                      <span class="flex-1 h-1.5 rounded-full bg-n-alpha-2">
                        <span
                          class="block h-full rounded-full bg-n-brand"
                          :style="{
                            width: `${(row.participacao_pct / maxShare) * 100}%`,
                          }"
                        />
                      </span>
                      <span class="w-12 text-xs text-right text-n-slate-11">
                        {{ percent(row.participacao_pct) }}
                      </span>
                    </span>
                  </td>
                  <td :class="TD" class="text-right text-n-slate-11">
                    {{
                      row.prazo_medio_dias === null
                        ? '—'
                        : label('TABLE.DAYS', {
                            days: formatNumber(row.prazo_medio_dias, 1),
                          })
                    }}
                  </td>
                  <td :class="TD">
                    <span
                      v-if="row.meta"
                      class="flex items-center gap-2 min-w-[8rem]"
                      :title="formatMoney(row.meta)"
                    >
                      <span class="flex-1 h-1.5 rounded-full bg-n-alpha-2">
                        <span
                          class="block h-full rounded-full bg-n-slate-11"
                          :style="{ width: `${Math.min(row.meta_pct, 100)}%` }"
                        />
                      </span>
                      <span class="w-12 text-xs text-right text-n-slate-11">
                        {{ percent(row.meta_pct) }}
                      </span>
                    </span>
                    <span v-else class="text-xs text-n-slate-10">
                      {{ label('TABLE.NO_GOAL') }}
                    </span>
                  </td>
                  <td
                    :class="TD"
                    class="text-right font-medium text-n-slate-12"
                  >
                    {{ formatMoney(row.comissao) }}
                  </td>
                </tr>
                <tr
                  v-if="expanded === row.tecnico"
                  class="border-b border-n-weak"
                >
                  <td colspan="11" class="px-4 py-3 bg-n-alpha-1">
                    <div
                      class="flex flex-wrap gap-x-6 gap-y-2 mb-3 text-xs text-n-slate-11"
                    >
                      <span>
                        {{ label('DETAIL.CLIENTS', { count: row.clientes }) }}
                      </span>
                      <span v-if="Object.keys(row.atendimentos).length">
                        {{ label('DETAIL.ATTENDANCE') }}
                        {{
                          Object.entries(row.atendimentos)
                            .map(([kind, count]) => `${kind} (${count})`)
                            .join(', ')
                        }}
                      </span>
                      <span v-if="Object.keys(row.vendedores).length">
                        {{ label('DETAIL.SELLERS') }}
                        {{
                          Object.entries(row.vendedores)
                            .map(([name, count]) => `${name} (${count})`)
                            .join(', ')
                        }}
                      </span>
                    </div>
                    <table class="w-full text-xs" data-tech-orders>
                      <thead>
                        <tr class="text-left text-n-slate-10">
                          <th class="py-1 pr-3 font-medium">
                            {{ label('DETAIL.ORDER') }}
                          </th>
                          <th class="py-1 pr-3 font-medium">
                            {{ label('DETAIL.ATTENDANCE_TYPE') }}
                          </th>
                          <th class="py-1 pr-3 font-medium">
                            {{ label('DETAIL.OS') }}
                          </th>
                          <th class="py-1 pr-3 font-medium">
                            {{ label('DETAIL.NOTES') }}
                          </th>
                          <th class="py-1 pr-3 font-medium">
                            {{ label('DETAIL.CLIENT') }}
                          </th>
                          <th class="py-1 pr-3 font-medium">
                            {{ label('DETAIL.SELLER') }}
                          </th>
                          <th class="py-1 font-medium text-right">
                            {{ label('DETAIL.CREDIT') }}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr
                          v-for="sale in salesOf(row.tecnico)"
                          :key="`${sale.unidade}:${sale.pedido}`"
                          class="border-t border-n-weak"
                          :class="sale.linha.fora_da_soma && 'text-n-slate-10'"
                        >
                          <td class="py-1.5 pr-3 whitespace-nowrap">
                            <button
                              type="button"
                              class="p-0 font-medium text-n-blue-11 hover:underline"
                              @click.stop="
                                openRecord('sales', sale.unidade, sale.pedido)
                              "
                            >
                              {{
                                label('DETAIL.ORDER_NUMBER', {
                                  number: sale.pedido,
                                })
                              }}
                            </button>
                            <span class="text-n-slate-10">
                              · {{ companyName(sale.unidade) }}
                            </span>
                          </td>
                          <td class="py-1.5 pr-3 whitespace-nowrap">
                            <span class="text-n-slate-12">
                              {{ sale.linha.atendimento || '—' }}
                            </span>
                            <span
                              v-if="sale.linha.fora_da_soma"
                              class="px-1 ml-1 text-[10px] font-medium rounded bg-n-alpha-2 text-n-slate-11"
                              :title="label('EXCLUDED.BADGE_HINT')"
                            >
                              {{ label('EXCLUDED.BADGE') }}
                            </span>
                          </td>
                          <td class="py-1.5 pr-3 whitespace-nowrap">
                            <template v-if="sale.linha.os">
                              <span
                                class="px-1 mr-1 text-[10px] font-medium rounded"
                                :class="
                                  sale.origem === 'erp'
                                    ? 'bg-n-alpha-2 text-n-slate-11'
                                    : 'bg-n-amber-3 text-n-amber-11'
                                "
                                :title="
                                  label(
                                    `DETAIL.ORIGIN_${sale.origem === 'erp' ? 'ERP' : 'CHAT'}_HINT`
                                  )
                                "
                              >
                                {{
                                  label(
                                    `DETAIL.ORIGIN_${sale.origem === 'erp' ? 'ERP' : 'CHAT'}`
                                  )
                                }}
                              </span>
                              <button
                                type="button"
                                class="p-0 font-medium text-n-blue-11 hover:underline"
                                @click.stop="
                                  openRecord(
                                    'orders',
                                    sale.unidade,
                                    sale.linha.os
                                  )
                                "
                              >
                                {{ sale.linha.os }}
                              </button>
                              <template v-if="sale.linha.parte < 100">
                                · {{ percent(sale.linha.parte) }}
                              </template>
                            </template>
                            <button
                              v-else
                              type="button"
                              class="inline-flex items-center gap-1 px-1.5 py-0.5 text-[11px] font-medium rounded bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4"
                              @click.stop="
                                openRecord('sales', sale.unidade, sale.pedido)
                              "
                            >
                              <Icon icon="i-lucide-link" class="size-3" />
                              {{ label('DETAIL.LINK_OS') }}
                            </button>
                          </td>
                          <td class="py-1.5 pr-3">
                            <span class="flex flex-wrap items-center gap-1">
                              <button
                                v-for="note in sale.notas"
                                :key="`${note.tipo}:${note.numero}`"
                                type="button"
                                class="px-1.5 py-0.5 text-[11px] rounded bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 whitespace-nowrap"
                                :title="formatMoney(note.total)"
                                @click.stop="
                                  openRecord(
                                    note.kind ||
                                      (note.tipo === 'NF-e'
                                        ? 'invoices'
                                        : 'service_invoices'),
                                    sale.unidade,
                                    note.codigo || note.numero
                                  )
                                "
                              >
                                {{ note.tipo }} {{ note.numero }}
                              </button>
                              <span class="text-n-slate-10 whitespace-nowrap">
                                {{ formatDate(sale.data_nota) }}
                              </span>
                            </span>
                          </td>
                          <td class="py-1.5 pr-3 text-n-slate-12">
                            {{ sale.cliente }}
                          </td>
                          <td class="py-1.5 pr-3 text-n-slate-11">
                            {{ sale.vendedor }}
                          </td>
                          <td
                            class="py-1.5 text-right tabular-nums"
                            :class="
                              sale.linha.fora_da_soma
                                ? 'line-through text-n-slate-10'
                                : 'text-n-slate-12'
                            "
                          >
                            {{
                              formatMoney((sale.total * sale.linha.parte) / 100)
                            }}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
      </section>

      <TechnicianReportLists :data="data" @open="openRecord" />
    </template>
    <TechnicianReportSettings ref="settingsRef" @saved="load" />
    <ErpRecordPanel
      v-if="opened"
      :key="`${opened.kind}:${opened.company}:${opened.number}`"
      floating
      :kind="opened.kind"
      :company="opened.company"
      :number="opened.number"
      @close="opened = null"
      @changed="load"
    />
  </div>
</template>
