<script setup>
// OUTSIDER: bloco "Orçamentos de peças e serviços" do contato (painel da conversa, aba CRM e negócio). Junta os
// orçamentos feitos no chat (rascunhos e gravados) com o espelho dos orçamentos do ERP (os feitos no Mais Prático):
// o mesmo orçamento aparece uma vez só. PDF, Enviar e Copiar valem para os dois; o do ERP vira registro na hora.
// Mostra os 5 mais novos; "Ver todos no ERP" abre a seção ERP filtrada pelos clientes deste contato (todo o histórico).
// Orçamento em NEGOCIAÇÃO, sem OS e sem pedido, numa unidade liberada: "Converter em OS" (ErpQuoteConvertDialog).
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpBudgetDrawer from './ErpBudgetDrawer.vue';
import ErpPdfDialog from './ErpPdfDialog.vue';
import ErpQuoteConvertDialog from '../orders/ErpQuoteConvertDialog.vue';
import { isNegotiation } from '../orders/orderHelpers';
import {
  ERP_ROUTE,
  erpState,
  formatDate,
  formatMoney,
  quoteClass,
  withLoadingRetry,
  erpErrorMessage,
  companyName,
} from '../erpStore';
import { budgetErrorMessage, quoteKey, reasonText } from './budgetHelpers';
import { erpTabs } from '../sidebar';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
  opportunityId: { type: Number, default: null },
});

const { t } = useI18n();
const loading = ref(false);
const failure = ref('');
const budgets = ref([]);
const mirror = ref([]);
const mirrorLoading = ref(false);
const mirrorFailure = ref('');
const busy = ref('');
const showAll = ref(false);
const drawerRef = ref(null);
const pdfRef = ref(null);
const convertRef = ref(null);
// orçamentos convertidos agora pelo chat ({ unidade:número => OS }): o espelho do ERP só atualiza depois
const converted = ref({});

const LIMIT = 5;
const route = useRoute();
// a aba Orçamentos da seção ERP (com o filtro do contato), quando a pessoa abre ela
const allInErp = computed(() =>
  erpTabs().some(item => item.name === 'orcamentos')
    ? {
        name: ERP_ROUTE,
        params: { accountId: route.params.accountId, tab: 'orcamentos' },
        query: { contact: props.contactId },
      }
    : null
);

const context = () => ({
  contact_id: props.contactId,
  conversation_id: props.conversationId || undefined,
  opportunity_id: props.opportunityId || undefined,
});

const loadBudgets = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.budgets(props.contactId);
    budgets.value = data.budgets || [];
  } catch (error) {
    failure.value = budgetErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

// espelho do ERP: na primeira vez é montado no Sidekiq (202) e a tela tenta de novo sozinha
const loadMirror = async () => {
  if (!erpState.quotesEnabled) return;
  mirrorLoading.value = true;
  mirrorFailure.value = '';
  try {
    const { data } = await withLoadingRetry(
      () => ErpAPI.quotes(props.contactId),
      { tries: 10, wait: 3000 }
    );
    mirror.value = data.quotes || [];
  } catch (error) {
    mirrorFailure.value = erpErrorMessage(t, error);
  } finally {
    mirrorLoading.value = false;
  }
};

const load = () => Promise.all([loadBudgets(), loadMirror()]);

watch(() => props.contactId, load, { immediate: true });

const dateOf = row =>
  row.quote?.DataCadastro ||
  row.budget?.erp_created_at ||
  row.budget?.updated_at ||
  '';

// rascunhos primeiro; depois os do ERP (do chat ou do Mais Prático), mais novos primeiro
const rows = computed(() => {
  const byKey = new Map(
    mirror.value.map(quote => [
      quoteKey(quote.Banco, quote.CodigoOrcamento),
      quote,
    ])
  );
  const used = new Set();
  const local = budgets.value.map(budget => {
    const key =
      budget.erp_number && quoteKey(budget.company, budget.erp_number);
    const quote = key ? byKey.get(key) : null;
    if (quote) used.add(key);
    return { key: `chat-${budget.id}`, budget, quote };
  });
  const erpOnly = mirror.value
    .filter(quote => !used.has(quoteKey(quote.Banco, quote.CodigoOrcamento)))
    .map(quote => ({
      key: `erp-${quote.Banco}-${quote.CodigoOrcamento}`,
      budget: null,
      quote,
    }));
  const isRecorded = row =>
    row.quote || ['created', 'imported'].includes(row.budget?.status);
  const byDate = (a, b) => String(dateOf(b)).localeCompare(String(dateOf(a)));
  return [
    ...local.filter(row => !isRecorded(row)).sort(byDate),
    ...[...local.filter(isRecorded), ...erpOnly].sort(byDate),
  ];
});

const visible = computed(() =>
  showAll.value ? rows.value : rows.value.slice(0, LIMIT)
);

const upsert = budget => {
  const exists = budgets.value.some(item => item.id === budget.id);
  budgets.value = exists
    ? budgets.value.map(item => (item.id === budget.id ? budget : item))
    : [budget, ...budgets.value];
};

const removed = id => {
  budgets.value = budgets.value.filter(item => item.id !== id);
};

const run = async (key, action) => {
  busy.value = key;
  try {
    await action();
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const create = () =>
  run('new', async () => {
    const { data } = await ErpAPI.createBudget(context());
    upsert(data.budget);
    drawerRef.value?.open(data.budget, { focus: true });
  });

// orçamento feito no Mais Prático: vira registro do chat (para PDF, envio e cópia)
const ensureBudget = async row => {
  if (row.budget) return row.budget;
  const { data } = await ErpAPI.importBudget({
    ...context(),
    company: row.quote.Banco,
    number: row.quote.CodigoOrcamento,
    name: row.quote.Cliente,
  });
  upsert(data.budget);
  return data.budget;
};

const openRow = row =>
  run(`open-${row.key}`, async () => {
    const budget = await ensureBudget(row);
    drawerRef.value?.open(budget);
  });

const pdf = row =>
  run(`pdf-${row.key}`, async () => {
    const budget = await ensureBudget(row);
    pdfRef.value?.open(budget.id);
  });

const copy = row =>
  run(`copy-${row.key}`, async () => {
    const budget = await ensureBudget(row);
    const { data } = await ErpAPI.copyBudget(budget.id, context());
    upsert(data.budget);
    drawerRef.value?.open(data.budget, { focus: true });
  });

const isDraftRow = row =>
  !row.quote && ['draft', 'submitting'].includes(row.budget?.status);

const draftChip = budget => {
  if (budget.status === 'submitting' && !budget.stuck)
    return {
      text: t('OUTSIDER_ERP.BUDGET.LIST.SUBMITTING'),
      class: 'bg-n-blue-3 text-n-blue-11',
    };
  if (budget.error || budget.stuck)
    return {
      text: t('OUTSIDER_ERP.BUDGET.LIST.FAILED'),
      class: 'bg-n-ruby-3 text-n-ruby-11',
    };
  return {
    text: t('OUTSIDER_ERP.BUDGET.LIST.NOT_RECORDED'),
    class: 'bg-n-alpha-2 text-n-slate-11',
  };
};

const convertible = row => {
  const quote = row.quote;
  if (!quote || !erpState.canConvertQuote) return false;
  if (!erpState.orderCompanies.includes(quote.Banco)) return false;
  if (converted.value[quoteKey(quote.Banco, quote.CodigoOrcamento)])
    return false;
  return (
    isNegotiation(quote.Status) &&
    !Number(quote.OrdemServico) &&
    !Number(quote.Pedido)
  );
};

const convert = row =>
  convertRef.value?.open({
    company: row.quote.Banco,
    number: row.quote.CodigoOrcamento,
    customerCode: row.quote.CodigoCliente,
    customerName: row.quote.Cliente,
    contactId: props.contactId,
    conversationId: props.conversationId,
  });

const onConverted = draft => {
  if (draft.status !== 'created') return;
  converted.value = {
    ...converted.value,
    [quoteKey(draft.company, draft.quote_number)]: draft.erp_number,
  };
};

const lastSend = budget => {
  const send = budget?.last_send;
  if (!send) return '';
  return t(`OUTSIDER_ERP.BUDGET.LIST.SENT_${send.channel.toUpperCase()}`, {
    date: formatDate(send.created_at),
  });
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <Button
      size="sm"
      icon="i-lucide-plus"
      class="w-full"
      :label="t('OUTSIDER_ERP.BUDGET.LIST.NEW')"
      :is-loading="busy === 'new'"
      @click="create"
    />

    <div v-if="loading && !budgets.length" class="flex justify-center p-2">
      <Spinner class="size-4 text-n-slate-10" />
    </div>
    <p v-else-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
      <button type="button" class="underline" @click="load">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>

    <article
      v-for="row in visible"
      :key="row.key"
      class="flex flex-col gap-1.5 p-3 text-sm border rounded-xl bg-n-solid-1"
      :class="
        isDraftRow(row) ? 'border-dashed border-n-strong' : 'border-n-weak'
      "
    >
      <!-- rascunho do chat -->
      <template v-if="isDraftRow(row)">
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium truncate text-n-slate-12">
            {{ t('OUTSIDER_ERP.BUDGET.LIST.DRAFT') }}
          </span>
          <span
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full shrink-0"
            :class="draftChip(row.budget).class"
          >
            <Spinner
              v-if="row.budget.status === 'submitting' && !row.budget.stuck"
              class="size-3"
            />
            {{ draftChip(row.budget).text }}
          </span>
        </div>
        <span class="text-xs truncate text-n-slate-11">
          {{
            t('OUTSIDER_ERP.BUDGET.LIST.DRAFT_LINE', {
              count: row.budget.items_count,
              total: formatMoney(row.budget.total),
              date: formatDate(row.budget.updated_at),
            })
          }}
        </span>
        <span
          v-if="row.budget.customer_name || row.budget.user"
          class="text-xs truncate text-n-slate-10"
        >
          {{
            [row.budget.customer_name, row.budget.user?.name]
              .filter(Boolean)
              .join(' · ')
          }}
        </span>
        <span
          v-if="row.budget.error"
          class="text-xs text-n-ruby-11 line-clamp-2"
        >
          {{ reasonText(t, row.budget.error) }}
        </span>
        <div class="flex gap-1.5">
          <Button
            size="xs"
            variant="faded"
            color="slate"
            :label="
              row.budget.can_edit
                ? t('OUTSIDER_ERP.BUDGET.LIST.CONTINUE')
                : t('OUTSIDER_ERP.BUDGET.LIST.OPEN')
            "
            :is-loading="busy === `open-${row.key}`"
            @click="openRow(row)"
          />
        </div>
      </template>

      <!-- orçamento no ERP (feito no chat ou no Mais Prático) -->
      <template v-else>
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium truncate text-n-slate-12">
            {{
              t('OUTSIDER_ERP.QUOTES.CODE', {
                code: row.quote?.CodigoOrcamento || row.budget.erp_number,
              })
            }}
            <span class="text-xs font-normal text-n-slate-10">
              {{ companyName(row.quote?.Banco || row.budget.company) }}
            </span>
          </span>
          <span
            v-if="row.quote?.Status"
            class="px-2 py-0.5 text-xs rounded-full shrink-0"
            :class="quoteClass(row.quote.Status)"
          >
            {{ row.quote.Status }}
          </span>
          <span
            v-else
            class="px-2 py-0.5 text-xs rounded-full shrink-0 bg-n-teal-3 text-n-teal-11"
          >
            {{ t('OUTSIDER_ERP.BUDGET.LIST.RECORDED') }}
          </span>
        </div>
        <div class="flex flex-wrap items-baseline justify-between gap-x-3">
          <span
            v-if="row.quote || row.budget.status === 'created'"
            class="font-semibold tabular-nums text-n-slate-12"
          >
            {{
              formatMoney(row.quote ? row.quote.ValorTotal : row.budget.total)
            }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              [formatDate(dateOf(row)), row.quote?.Vendedor]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
        </div>
        <span
          v-if="
            row.quote &&
            converted[quoteKey(row.quote.Banco, row.quote.CodigoOrcamento)]
          "
          class="text-xs text-n-teal-11"
        >
          {{
            t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.CONVERTED_ROW', {
              os: converted[
                quoteKey(row.quote.Banco, row.quote.CodigoOrcamento)
              ],
            })
          }}
        </span>
        <span
          v-if="row.quote?.OrdemServico || row.quote?.Pedido"
          class="text-xs text-n-slate-11"
        >
          <template v-if="row.quote.OrdemServico">
            {{ t('OUTSIDER_ERP.ORDER.CODE', { code: row.quote.OrdemServico }) }}
          </template>
          <template v-if="row.quote.Pedido">
            {{ t('OUTSIDER_ERP.QUOTES.ORDER', { code: row.quote.Pedido }) }}
          </template>
        </span>
        <span
          v-if="lastSend(row.budget)"
          class="flex items-center gap-1 text-xs text-n-teal-11"
        >
          <Icon icon="i-lucide-check-check" class="size-3.5" />
          {{ lastSend(row.budget) }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <Button
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-file-text"
            :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.PDF_SHORT')"
            :is-loading="busy === `pdf-${row.key}`"
            @click="pdf(row)"
          />
          <Button
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-send"
            :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.SEND')"
            :is-loading="busy === `open-${row.key}`"
            @click="openRow(row)"
          />
          <Button
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-copy"
            :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.COPY')"
            :is-loading="busy === `copy-${row.key}`"
            @click="copy(row)"
          />
          <Button
            v-if="convertible(row)"
            size="xs"
            variant="faded"
            color="teal"
            icon="i-lucide-wrench"
            :label="t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.BUTTON')"
            data-erp-convert-quote
            @click="convert(row)"
          />
        </div>
      </template>
    </article>

    <p
      v-if="!loading && !failure && !rows.length && !mirrorLoading"
      class="mb-0 text-xs text-n-slate-10"
    >
      {{ t('OUTSIDER_ERP.BUDGET.LIST.EMPTY') }}
    </p>
    <span
      v-if="mirrorLoading"
      class="flex items-center gap-2 text-xs text-n-slate-10"
    >
      <Spinner class="size-3" />
      {{ t('OUTSIDER_ERP.QUOTES.LOADING') }}
    </span>
    <p v-else-if="mirrorFailure" class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_ERP.BUDGET.LIST.MIRROR_FAILED') }}
      <button type="button" class="underline" @click="loadMirror">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>
    <router-link
      v-if="allInErp"
      :to="allInErp"
      class="inline-flex items-center self-start gap-1 text-xs font-medium text-n-blue-11 hover:underline"
    >
      {{ t('OUTSIDER_ERP.CONTACT.ALL_QUOTES') }}
      <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
    </router-link>
    <button
      v-else-if="rows.length > LIMIT"
      type="button"
      class="self-start text-xs text-n-blue-11 hover:underline"
      @click="showAll = !showAll"
    >
      {{
        showAll
          ? t('OUTSIDER_ERP.CONTACT.SHOW_LESS')
          : t('OUTSIDER_ERP.CONTACT.SHOW_ALL', { count: rows.length })
      }}
    </button>

    <ErpBudgetDrawer
      ref="drawerRef"
      :contact-id="contactId"
      :conversation-id="conversationId"
      :opportunity-id="opportunityId"
      @changed="upsert"
      @removed="removed"
    />
    <ErpPdfDialog ref="pdfRef" />
    <ErpQuoteConvertDialog ref="convertRef" @converted="onConverted" />
  </div>
</template>
