<script setup>
// OUTSIDER: o que ficou fora do relatório dos técnicos: pedidos faturados no período sem técnico informado (com o link
// para informar no pedido) e pedidos com técnico informado que ainda não têm nota válida (entram quando faturarem).
// Pedido e nota abrem o painel de detalhe por cima do relatório (evento open, quem abre é o TechnicianReport).
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatMoney, formatDate, companyName } from '../../erp/erpStore';

defineProps({
  data: { type: Object, required: true },
});

const emit = defineEmits(['open']);

const noteKind = note =>
  note.kind || (note.tipo === 'NF-e' ? 'invoices' : 'service_invoices');

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
                <button
                  type="button"
                  class="inline-flex items-center gap-1 p-0 font-medium text-n-blue-11 hover:underline"
                  @click="emit('open', 'sales', sale.unidade, sale.pedido)"
                >
                  {{ label('DETAIL.ORDER_NUMBER', { number: sale.pedido }) }}
                  <Icon icon="i-lucide-link" class="size-3.5" />
                </button>
                <span class="block text-[11px] text-n-slate-10">
                  {{ companyName(sale.unidade) }}
                </span>
              </td>
              <td :class="TD" class="text-xs text-n-slate-11">
                <span class="flex flex-wrap gap-1">
                  <button
                    v-for="note in sale.notas"
                    :key="`${note.tipo}:${note.numero}`"
                    type="button"
                    class="px-1.5 py-0.5 text-[11px] rounded bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 whitespace-nowrap"
                    @click="
                      emit(
                        'open',
                        noteKind(note),
                        sale.unidade,
                        note.codigo || note.numero
                      )
                    "
                  >
                    {{ note.tipo }} {{ note.numero }}
                  </button>
                </span>
                <span class="block mt-0.5">{{
                  formatDate(sale.data_nota)
                }}</span>
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
                <button
                  type="button"
                  class="p-0 font-medium text-n-blue-11 hover:underline"
                  @click="emit('open', 'sales', sale.unidade, sale.pedido)"
                >
                  {{ label('DETAIL.ORDER_NUMBER', { number: sale.pedido }) }}
                </button>
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
