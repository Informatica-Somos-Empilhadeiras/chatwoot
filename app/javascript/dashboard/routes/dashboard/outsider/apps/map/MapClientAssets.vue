<script setup>
// OUTSIDER (Maps): lateral direita do Mapa dos agendamentos: as máquinas no cliente (locadas nos contratos ativos e as
// do próprio cliente) e as OS abertas dele. Tocar abre o detalhe na seção ERP.
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  info: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();

const base = () => `/app/accounts/${route.params.accountId}/erp`;
const orderLink = order => `${base()}/os?open=${order.company}:${order.code}`;
const machineLink = machine =>
  `${base()}/maquinas?open=${machine.banco}:${machine.numero || machine.maquina}`;
const brDate = value => {
  const [y, m, d] = String(value || '')
    .slice(0, 10)
    .split('-');
  return d ? `${d}/${m}/${y}` : '';
};
const machineName = machine =>
  [machine.descricao, machine.modelo, machine.capacidade]
    .filter(Boolean)
    .join(' · ') || t('OUTSIDER_MAPS.MAP.MACHINE');
</script>

<template>
  <div class="flex flex-col gap-3" data-map-client-assets>
    <section class="flex flex-col gap-1.5">
      <span
        class="text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_MAPS.MAP.MACHINES') }}
      </span>
      <p v-if="!info.machines?.length" class="mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_MAPS.MAP.NO_MACHINES') }}
      </p>
      <a
        v-for="(machine, index) in info.machines || []"
        :key="index"
        :href="machineLink(machine)"
        class="block p-2 border rounded-lg border-n-weak hover:bg-n-alpha-1"
        data-map-machine
      >
        <span class="flex flex-wrap items-center gap-1.5">
          <b class="text-sm text-n-slate-12">{{ machineName(machine) }}</b>
          <span
            class="px-1.5 rounded-full text-[10px] font-bold"
            :class="
              machine.kind === 'rented'
                ? 'bg-n-blue-3 text-n-blue-11'
                : 'bg-n-amber-3 text-n-amber-11'
            "
          >
            {{
              machine.kind === 'rented'
                ? t('OUTSIDER_MAPS.MAP.RENTED')
                : t('OUTSIDER_MAPS.MAP.OWN')
            }}
          </span>
        </span>
        <span class="block text-xs text-n-slate-11">
          {{
            [
              machine.serie &&
                t('OUTSIDER_MAPS.MAP.SERIAL', { value: machine.serie }),
              machine.contrato &&
                t('OUTSIDER_MAPS.MAP.CONTRACT', { value: machine.contrato }),
              machine.situacao,
            ]
              .filter(Boolean)
              .join(' · ')
          }}
        </span>
      </a>
    </section>

    <section class="flex flex-col gap-1.5">
      <span
        class="text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_MAPS.MAP.OPEN_ORDERS') }}
      </span>
      <p v-if="!info.orders?.length" class="mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_MAPS.MAP.NO_ORDERS') }}
      </p>
      <a
        v-for="order in info.orders || []"
        :key="`${order.company}-${order.code}`"
        :href="orderLink(order)"
        class="block p-2 border rounded-lg border-n-weak hover:bg-n-alpha-1"
        data-map-order
      >
        <span class="flex flex-wrap items-center gap-1.5 text-sm">
          <b class="text-n-slate-12">
            {{ t('OUTSIDER_MAPS.MAP.ORDER', { code: order.code }) }}
          </b>
          <span class="text-n-slate-11">{{ order.status }}</span>
          <span
            v-if="order.substatus"
            class="px-1.5 rounded-full text-[10px] font-bold bg-n-teal-3 text-n-teal-11"
          >
            {{ order.substatus }}
          </span>
        </span>
        <span class="block text-xs text-n-slate-11">
          {{
            [
              order.kind,
              order.machine,
              order.technician,
              order.forecast &&
                t('OUTSIDER_MAPS.MAP.FORECAST', {
                  date: brDate(order.forecast),
                }),
            ]
              .filter(Boolean)
              .join(' · ')
          }}
        </span>
      </a>
      <p class="mb-0 text-[11px] text-n-slate-10">
        <Icon icon="i-lucide-mouse-pointer-click" class="size-3 inline" />
        {{ t('OUTSIDER_MAPS.MAP.ASSETS_HINT') }}
      </p>
    </section>
  </div>
</template>
