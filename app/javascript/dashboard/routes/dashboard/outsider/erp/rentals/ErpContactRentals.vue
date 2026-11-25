<script setup>
// OUTSIDER: bloco "Contratos e máquinas" no ERP do contato (painel da conversa): os contratos dos clientes do ERP ligados
// ao contato (ativos primeiro, com a vigência, o valor e a próxima fatura), as máquinas que estão com o cliente por esses
// contratos (com a situação de agora: no cliente, em OS...) e as máquinas que são do próprio cliente. Cada item abre o
// painel dele na seção ERP; "Ver contratos/máquinas no ERP" abre as abas filtradas pelo contato.
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  ERP_ROUTE,
  erpErrorMessage,
  formatDate,
  formatMoney,
} from '../erpStore';
import { statusClass } from '../records/recordsConfig';
import {
  contractDue,
  contractTypeLabel,
  hourMeter,
  machineName,
  machineTag,
  periodKey,
} from './rentalHelpers';

const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const route = useRoute();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const data = ref(null);
const loading = ref(false);
const failure = ref('');

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const response = await ErpAPI.contactRentals(props.contactId);
    data.value = response.data;
  } catch (error) {
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};
watch(() => props.contactId, load, { immediate: true });

const contracts = computed(() => data.value?.contracts || []);
// máquina do cliente que já aparece embaixo de um contrato não se repete na lista das próprias
const machines = computed(() => {
  const listed = new Set(
    contracts.value.flatMap(row =>
      (row.maquinas || []).map(item => `${item.base}:${item.maquina}`)
    )
  );
  return (data.value?.machines || []).filter(
    row => !listed.has(`${row.banco}:${row.numero}`)
  );
});
const empty = computed(
  () => data.value && !contracts.value.length && !machines.value.length
);

const to = (tab, query) => ({
  name: ERP_ROUTE,
  params: { accountId: route.params.accountId, tab },
  query,
});
const openContract = row =>
  to('contratos', { open: `${row.banco}:${row.numero}` });
const openMachine = row =>
  to('maquinas', {
    open: `${row.base || row.banco}:${row.maquina || row.numero}`,
  });

const contractLine = row => {
  const key = periodKey(row.periodicidade);
  return [
    row.inicio || row.termino
      ? `${formatDate(row.inicio).slice(0, 5) || '—'} ${rt('CONTRACT.TO')} ${formatDate(row.termino) || '—'}`
      : '',
    Number(row.parcela)
      ? `${formatMoney(row.parcela)}${key ? ` ${rt(key)}` : ''}`
      : Number(row.total) && formatMoney(row.total),
  ]
    .filter(Boolean)
    .join(' · ');
};
const contractStatus = row => {
  const due = contractDue(row);
  return due ? rt(`DUE.${due.key}`, { n: due.days }) : row.status;
};

// "No cliente · 3.412 h · última OS 14/10" / "OS 2080 aberta"
const machineLine = row =>
  [
    row.situacao === 'EM OS' && Number(row.os_aberta)
      ? rt('MACHINE.ORDER_OPEN', { number: row.os_aberta })
      : '',
    hourMeter(row.horimetro),
    row.ultima_os &&
      rt('MACHINE.LAST_ORDER', { date: formatDate(row.ultima_os).slice(0, 5) }),
  ]
    .filter(Boolean)
    .join(' · ');
const machineStatus = row =>
  ['LOCADA', 'EM CONTRATO'].includes(row.situacao)
    ? rt('MACHINE.AT_CLIENT')
    : row.situacao;

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
const CARD =
  'flex items-start gap-2 px-2.5 py-2 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak hover:bg-n-alpha-1';
</script>

<template>
  <div class="flex flex-col gap-2" data-contact-rentals>
    <span :class="LABEL">{{ rt('CONTACT.TITLE') }}</span>
    <div v-if="loading && !data" class="flex justify-center p-2">
      <Spinner class="text-n-slate-10" />
    </div>
    <p v-else-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
      <button type="button" class="underline" @click="load">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>
    <p v-else-if="empty" class="mb-0 text-xs text-n-slate-10">
      {{ rt('CONTACT.EMPTY') }}
    </p>
    <template v-else-if="data">
      <template v-for="row in contracts" :key="`${row.banco}:${row.numero}`">
        <router-link :to="openContract(row)" :class="CARD" class="bg-n-alpha-1">
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-xs font-medium truncate text-n-teal-11">
              {{ rt('CONTRACT.ONE', { number: row.numero }) }} ·
              {{ contractTypeLabel(t, row.tipo) }}
            </span>
            <span class="text-[11px] text-n-slate-10">{{
              contractLine(row)
            }}</span>
          </div>
          <span
            v-if="row.status"
            class="px-1.5 py-0.5 text-[10px] font-medium rounded-full shrink-0"
            :class="
              contractDue(row)
                ? 'bg-n-amber-3 text-n-amber-11'
                : statusClass(row.status)
            "
          >
            {{ contractStatus(row) }}
          </span>
        </router-link>
        <router-link
          v-for="machine in row.maquinas || []"
          :key="`${row.numero}-${machine.maquina}`"
          :to="openMachine(machine)"
          :class="CARD"
          class="ml-3"
        >
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-xs truncate text-n-slate-12">
              <span class="font-medium text-n-teal-11">{{
                machineName(machine)
              }}</span>
              · {{ machineTag(machine) }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ machineLine(machine) }}
            </span>
          </div>
          <span
            class="px-1.5 py-0.5 text-[10px] font-medium rounded-full shrink-0"
            :class="
              statusClass(machine.situacao === 'EM OS' ? 'EM OS' : 'DISPONÍVEL')
            "
          >
            {{ machineStatus(machine) }}
          </span>
        </router-link>
      </template>

      <template v-if="machines.length">
        <span :class="LABEL" class="mt-1">
          {{ rt('CONTACT.OWN_MACHINES', { n: machines.length }) }}
        </span>
        <router-link
          v-for="machine in machines"
          :key="`${machine.banco}:${machine.numero}`"
          :to="openMachine(machine)"
          :class="CARD"
        >
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-xs truncate text-n-slate-12">
              {{ machineName(machine) }} · {{ machineTag(machine) }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{
                [
                  Number(machine.contrato)
                    ? rt('CONTRACT.ONE', { number: machine.contrato })
                    : rt('MACHINE.NO_CONTRACT'),
                  machineLine(machine),
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </div>
          <span
            v-if="machine.situacao === 'EM OS'"
            class="px-1.5 py-0.5 text-[10px] font-medium rounded-full shrink-0"
            :class="statusClass('EM OS')"
          >
            {{ machine.situacao }}
          </span>
        </router-link>
      </template>

      <div class="flex flex-wrap gap-2">
        <router-link
          :to="to('contratos', { contact: contactId })"
          class="inline-flex items-center gap-1.5 text-xs font-medium text-n-blue-11 hover:underline"
        >
          <Icon icon="i-lucide-file-signature" class="size-3.5" />
          {{ rt('CONTACT.SEE_CONTRACTS') }}
        </router-link>
        <router-link
          :to="to('maquinas', { contact: contactId })"
          class="inline-flex items-center gap-1.5 text-xs font-medium text-n-blue-11 hover:underline"
        >
          <Icon icon="i-lucide-forklift" class="size-3.5" />
          {{ rt('CONTACT.SEE_MACHINES') }}
        </router-link>
      </div>
    </template>
  </div>
</template>
