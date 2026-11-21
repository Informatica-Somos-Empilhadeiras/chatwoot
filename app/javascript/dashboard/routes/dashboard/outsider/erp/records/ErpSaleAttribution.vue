<script setup>
// OUTSIDER: técnico e OS de um pedido de venda, informados pelo vendedor no chat (Outsider::Erp::SaleAttributor). O
// Mais Prático não tem esses campos no pedido: isto fica só no Chatwoot, não muda o pedido do ERP e é a base do relatório
// de desempenho dos técnicos (que só conta o pedido faturado). Digitar a OS traz o técnico dela; se o vendedor ou o
// cliente da OS forem outros (ou se ela já estiver em outro pedido), só grava com a senha comercial. Com mais de uma OS,
// cada uma leva uma parte do valor do pedido.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpErrorMessage, formatDate, formatMoney } from '../erpStore';
import {
  budgetErrorMessage,
  formatNumber,
  parseNumber,
} from '../budgets/budgetHelpers';

const props = defineProps({
  company: { type: String, required: true },
  number: { type: Number, required: true },
  canEdit: { type: Boolean, default: false },
});

const emit = defineEmits(['changed']);

// o que impede de gravar mesmo com senha (o resto a senha comercial libera)
const BLOCKING = [
  'os_nao_encontrada',
  'sem_tecnico',
  'os_aberta',
  'os_cancelada',
];

const { t } = useI18n();
const loading = ref(true);
const failure = ref('');
const sale = ref({});
const saved = ref(null);
const suggestions = ref([]);
const editing = ref(false);
// linhas em edição: { os (texto), valor (texto, R$), info (a OS conferida no ERP), checking }
const rows = ref([]);
const code = ref('');
const password = ref('');
const saving = ref(false);

const total = computed(() => Number(sale.value.total) || 0);
const label = key => t(`OUTSIDER_ERP.SALE_ATTRIBUTION.${key}`);

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.saleAttribution(props.company, props.number);
    sale.value = data.pedido || {};
    saved.value = data.vinculo;
    suggestions.value = (data.sugestoes || []).filter(
      line => !line.divergencias?.includes('os_nao_encontrada')
    );
  } catch (error) {
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

watch(() => [props.company, props.number], load, { immediate: true });

// o que já está gravado, em R$ (parte do pedido)
const savedRows = computed(() =>
  (saved.value?.linhas || []).map(line => ({
    ...line,
    valor: (total.value * Number(line.parte || 0)) / 100,
  }))
);

const blank = (os = '', info = null) => ({
  os: String(os || ''),
  valor: '',
  info,
  checking: false,
});

// valores iguais entre as OS (o vendedor ajusta); uma OS só leva o pedido inteiro
const spread = () => {
  const share = rows.value.length ? total.value / rows.value.length : 0;
  rows.value = rows.value.map(row => ({
    ...row,
    valor: formatNumber(share),
  }));
};

const check = async row => {
  const os = Number(row.os);
  if (!os) {
    row.info = null;
    return;
  }
  if (row.info?.os === os) return;
  row.checking = true;
  try {
    const { data } = await ErpAPI.previewSaleAttribution(
      props.company,
      props.number,
      [os]
    );
    row.info = data.linhas?.[0] || null;
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    row.checking = false;
  }
};

const startEdit = (fromSuggestion = null) => {
  const source = fromSuggestion
    ? [blank(fromSuggestion.os, fromSuggestion)]
    : savedRows.value.map(line => ({
        ...blank(line.os),
        valor: formatNumber(line.valor),
      }));
  rows.value = source.length ? source : [blank()];
  if (fromSuggestion || !savedRows.value.length) spread();
  rows.value.filter(row => row.os && !row.info).forEach(check);
  code.value = '';
  password.value = '';
  editing.value = true;
};

const addRow = () => {
  rows.value = [...rows.value, blank()];
  spread();
};

const removeRow = index => {
  rows.value = rows.value.filter((_, position) => position !== index);
  spread();
};

const sumValues = computed(() =>
  rows.value.reduce((sum, row) => sum + parseNumber(row.valor, 0), 0)
);
const splitOk = computed(
  () =>
    rows.value.length < 2 ||
    !total.value ||
    Math.abs(sumValues.value - total.value) < 0.02
);
const divergences = computed(() =>
  rows.value.flatMap(row => row.info?.divergencias || [])
);
const blocking = computed(() =>
  divergences.value.some(item => BLOCKING.includes(item))
);
const needsPassword = computed(
  () => !blocking.value && divergences.value.length > 0
);
const canSave = computed(
  () =>
    rows.value.length &&
    rows.value.every(row => Number(row.os) && row.info && !row.checking) &&
    splitOk.value &&
    !blocking.value &&
    (!needsPassword.value ||
      (/^\d{1,9}$/.test(code.value.trim()) && password.value)) &&
    !saving.value
);

const percentOf = row => {
  if (rows.value.length < 2) return 100;
  if (!total.value) return 100 / rows.value.length;
  return (parseNumber(row.valor, 0) / total.value) * 100;
};

const save = async () => {
  if (!canSave.value) return;
  saving.value = true;
  try {
    const { data } = await ErpAPI.saveSaleAttribution(
      props.company,
      props.number,
      {
        lines: rows.value.map(row => ({
          os: Number(row.os),
          parte: Number(percentOf(row).toFixed(6)),
        })),
        approval: needsPassword.value
          ? { code: code.value.trim(), password: password.value }
          : undefined,
      }
    );
    saved.value = data;
    editing.value = false;
    useAlert(label('SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    password.value = '';
    saving.value = false;
  }
};

const remove = async () => {
  saving.value = true;
  try {
    await ErpAPI.removeSaleAttribution(props.company, props.number);
    saved.value = null;
    useAlert(label('REMOVED'));
    emit('changed');
    load();
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    saving.value = false;
  }
};

const reasonText = (item, info) =>
  t(`OUTSIDER_ERP.SALE_ATTRIBUTION.DIVERGENCES.${item.toUpperCase()}`, {
    vendedor: info?.vendedor || '—',
    cliente: info?.cliente || '—',
    pedido: info?.pedido_usado || '—',
  });

const INPUT =
  '!mb-0 h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 border rounded-xl border-n-brand/30 bg-n-brand/5"
  >
    <header class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex flex-col gap-0.5">
        <span
          class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
        >
          <Icon icon="i-lucide-hard-hat" class="size-4 text-n-brand" />
          {{ label('TITLE') }}
        </span>
        <span class="text-xs text-n-slate-10">{{ label('HINT') }}</span>
      </div>
      <span
        class="px-2 py-0.5 text-[11px] font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{ label('INTERNAL') }}
      </span>
    </header>

    <div v-if="loading" class="flex justify-center py-2">
      <Spinner class="size-4 text-n-slate-10" />
    </div>
    <p v-else-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
    </p>

    <template v-else-if="!editing">
      <div v-if="savedRows.length" class="flex flex-col gap-2">
        <div
          v-for="line in savedRows"
          :key="line.os"
          class="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 rounded-lg bg-n-solid-1"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ line.tecnico || label('NO_NAME') }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_ERP.SALE_ATTRIBUTION.OS', { number: line.os }) }}
          </span>
          <span class="flex-1" />
          <span
            v-if="savedRows.length > 1"
            class="text-xs tabular-nums text-n-slate-11"
          >
            {{ formatNumber(line.parte, line.parte % 1 ? 1 : 0) }}%
          </span>
          <span class="text-sm font-medium tabular-nums text-n-slate-12">
            {{ formatMoney(line.valor) }}
          </span>
        </div>
        <p class="mb-0 text-xs text-n-slate-10">
          {{
            t('OUTSIDER_ERP.SALE_ATTRIBUTION.BY', {
              name: saved.por || '—',
              date: formatDate(saved.em),
            })
          }}
          <template v-if="saved.aprovado_por">
            ·
            {{
              t('OUTSIDER_ERP.SALE_ATTRIBUTION.APPROVED_BY', {
                name: saved.aprovado_por,
              })
            }}
          </template>
        </p>
        <div v-if="canEdit" class="flex gap-2">
          <Button
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-pencil"
            :label="label('EDIT')"
            @click="startEdit()"
          />
          <Button
            size="sm"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            :label="label('REMOVE')"
            :is-loading="saving"
            @click="remove"
          />
        </div>
      </div>
      <div v-else class="flex flex-col gap-2">
        <p class="mb-0 text-sm text-n-slate-11">{{ label('EMPTY') }}</p>
        <div v-if="canEdit" class="flex flex-wrap gap-2">
          <button
            v-for="line in suggestions"
            :key="line.os"
            type="button"
            class="inline-flex items-center gap-1.5 h-8 px-3 text-xs font-medium rounded-lg bg-n-teal-9 text-white hover:bg-n-teal-10"
            @click="startEdit(line)"
          >
            <Icon icon="i-lucide-sparkles" class="size-3.5" />
            {{
              t('OUTSIDER_ERP.SALE_ATTRIBUTION.SUGGESTION', {
                number: line.os,
                name: line.tecnico || '—',
              })
            }}
          </button>
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="label('ADD')"
            @click="startEdit()"
          />
        </div>
      </div>
    </template>

    <div v-else class="flex flex-col gap-3">
      <div
        v-for="(row, index) in rows"
        :key="index"
        class="flex flex-col gap-2 p-3 rounded-lg bg-n-solid-1"
      >
        <div class="flex flex-wrap items-center gap-2">
          <input
            v-model="row.os"
            inputmode="numeric"
            :placeholder="label('OS_PLACEHOLDER')"
            :aria-label="label('OS_PLACEHOLDER')"
            :class="INPUT"
            class="w-32"
            @blur="check(row)"
            @keydown.enter.prevent="check(row)"
          />
          <Spinner v-if="row.checking" class="size-4 text-n-slate-10" />
          <span
            v-else-if="row.info?.tecnico"
            class="flex items-center gap-1 text-sm font-medium text-n-slate-12"
          >
            <Icon icon="i-lucide-hard-hat" class="size-4 text-n-teal-11" />
            {{ row.info.tecnico }}
          </span>
          <span class="flex-1" />
          <template v-if="rows.length > 1">
            <input
              v-model="row.valor"
              inputmode="decimal"
              :aria-label="label('VALUE')"
              :class="INPUT"
              class="w-32 text-right"
            />
            <span class="w-12 text-xs text-right tabular-nums text-n-slate-10">
              {{ formatNumber(percentOf(row), 1) }}%
            </span>
            <button
              type="button"
              class="flex items-center justify-center rounded-md size-7 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
              :aria-label="label('REMOVE_OS')"
              @click="removeRow(index)"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </template>
        </div>
        <p
          v-if="row.info?.situacao || row.info?.cliente"
          class="mb-0 text-xs text-n-slate-10"
        >
          {{
            [row.info.situacao, row.info.cliente, row.info.atendimento]
              .filter(Boolean)
              .join(' · ')
          }}
        </p>
        <p
          v-for="item in row.info?.divergencias || []"
          :key="item"
          class="flex items-start gap-1.5 mb-0 text-xs"
          :class="
            BLOCKING.includes(item) ? 'text-n-ruby-11' : 'text-n-amber-11'
          "
        >
          <Icon
            icon="i-lucide-triangle-alert"
            class="mt-0.5 size-3.5 shrink-0"
          />
          {{ reasonText(item, row.info) }}
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-if="rows.length < 10"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-plus"
          :label="label('ADD_OS')"
          @click="addRow"
        />
        <span
          v-if="rows.length > 1"
          class="text-xs tabular-nums"
          :class="splitOk ? 'text-n-slate-10' : 'text-n-ruby-11'"
        >
          {{
            t('OUTSIDER_ERP.SALE_ATTRIBUTION.SPLIT', {
              sum: formatMoney(sumValues),
              total: formatMoney(total),
            })
          }}
        </span>
      </div>

      <div
        v-if="needsPassword"
        class="flex flex-col gap-2 p-3 border rounded-lg border-n-amber-6 bg-n-amber-2"
      >
        <span class="text-sm font-medium text-n-amber-11">
          {{ label('PASSWORD_TITLE') }}
        </span>
        <span class="text-xs text-n-amber-11">
          {{ label('PASSWORD_HINT') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <input
            v-model="code"
            inputmode="numeric"
            autocomplete="off"
            :placeholder="t('OUTSIDER_ERP.BUDGET.DISCOUNT.CODE')"
            :class="INPUT"
            class="w-40"
          />
          <input
            v-model="password"
            type="password"
            autocomplete="new-password"
            :placeholder="t('OUTSIDER_ERP.BUDGET.DISCOUNT.PASSWORD')"
            :class="INPUT"
            class="w-40"
            @keydown.enter.prevent="save"
          />
        </div>
      </div>

      <div class="flex justify-end gap-2">
        <Button
          size="sm"
          variant="faded"
          color="slate"
          :label="t('OUTSIDER_ERP.CANCEL')"
          @click="editing = false"
        />
        <Button
          size="sm"
          icon="i-lucide-check"
          :label="label('SAVE')"
          :disabled="!canSave"
          :is-loading="saving"
          @click="save"
        />
      </div>
    </div>
  </section>
</template>
