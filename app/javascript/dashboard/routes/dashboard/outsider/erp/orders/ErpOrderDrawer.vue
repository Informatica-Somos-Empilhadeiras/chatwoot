<script setup>
// OUTSIDER: gaveta da Nova OS feita no chat (Outsider::Erp::OrderDraft), no mesmo jeito da gaveta do orçamento:
// rascunho que salva sozinho a cada mudança (cliente, máquina, tipo, técnico, datas, classe, defeitos, peças e
// serviços), "Gravar no ERP" grava no Sidekiq e a gaveta acompanha; parou no meio: "Tentar de novo" continua a mesma OS.
// Gravada (Nova OS ou conversão): o número oficial e o que foi conferido no ERP (ErpOrderResult), "Cancelar OS" (só muda
// a situação para CANCELADA) e o atalho para a OS na seção ERP.
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpPicker from '../components/ErpPicker.vue';
import ErpBudgetItems from '../budgets/ErpBudgetItems.vue';
import ErpOrderFields from './ErpOrderFields.vue';
import ErpOrderResult from './ErpOrderResult.vue';
import { erpTabs } from '../sidebar';
import {
  ERP_ROUTE,
  erpState,
  companyName,
  formatDate,
  formatMoney,
  withLoadingRetry,
} from '../erpStore';
import { parseNumber } from '../budgets/budgetHelpers';
import {
  draftChip,
  orderErrorMessage,
  orderReasonText,
  orderTotals,
} from './orderHelpers';

const props = defineProps({
  contactId: { type: Number, default: null },
});

const emit = defineEmits(['changed', 'removed']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const isOpen = ref(false);
const loading = ref(false);
const draft = ref(null);
const fields = ref({});
const items = ref([]);
const options = ref({});
// saved | pending | saving | error
const saveState = ref('saved');
const busy = ref('');
const confirmDelete = ref(false);
const confirmCancel = ref(false);
const picking = ref(false);
const pickCompany = ref('');
const pending = ref(null);
const itemsRef = ref(null);

const SAVE_DELAY = 800;
const POLL_EVERY = 2000;
const POLL_LIMIT = 120;
let saveTimer = null;
let pollTimer = null;
let polls = 0;
let chain = Promise.resolve();
let saved = '';

const status = computed(() => draft.value?.status);
const isRecorded = computed(() => status.value === 'created');
const isSubmitting = computed(
  () => status.value === 'submitting' && !draft.value?.stuck
);
const canEdit = computed(
  () =>
    status.value === 'draft' &&
    draft.value?.can_edit &&
    !draft.value?.erp_number
);
const title = computed(() =>
  isRecorded.value
    ? t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.RECORDED', {
        number: draft.value.erp_number,
      })
    : t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.NEW')
);
const chip = computed(() => (draft.value ? draftChip(t, draft.value) : null));
const totals = computed(() => orderTotals(items.value));
const erpUser = computed(() => options.value.erp_user);
const errorText = computed(() => orderReasonText(t, draft.value?.error));
const failedCheck = computed(() =>
  (draft.value?.checks || []).find(check => !check.ok)
);

// o que falta para gravar (o servidor confere tudo de novo, no ERP)
const missing = computed(() => {
  if (!draft.value || !canEdit.value) return '';
  if (!draft.value.customer_code) return 'sem_cliente';
  if (options.value.company && !erpUser.value) return 'usuario_erp';
  if (options.value.machine_required && !Number(fields.value.maquina))
    return 'maquina_obrigatoria';
  if (!fields.value.tipo_atendimento) return 'tipo_atendimento';
  if (!Number(fields.value.classe)) return 'classe';
  if (!items.value.length) return 'sem_itens';
  return '';
});

// a OS na seção ERP (aba OS aberta no perfil)
const erpLink = computed(() =>
  draft.value?.erp_number && erpTabs().some(item => item.name === 'os')
    ? {
        name: ERP_ROUTE,
        params: { accountId: route.params.accountId, tab: 'os' },
        query: { open: `${draft.value.company}:${draft.value.erp_number}` },
      }
    : null
);

// quantidade e valor sempre como número (o campo aceita "1.234,56" enquanto a pessoa digita)
const plainItems = list =>
  list.map(item => ({
    codigo: item.codigo,
    descricao: item.descricao,
    unidade: item.unidade,
    tipo: Number(item.tipo) === 1 ? 1 : 0,
    quantidade: parseNumber(item.quantidade, 1),
    preco: parseNumber(item.preco),
  }));
const payload = () => ({
  fields: fields.value,
  items: plainItems(items.value),
});
const snapshot = () => JSON.stringify(payload());

const fill = data => {
  draft.value = data;
  fields.value = { ...(data.fields || {}) };
  items.value = (data.items || []).map(item => ({
    ...item,
    quantidade: parseNumber(item.quantidade, 1),
    preco: parseNumber(item.preco),
  }));
  saved = snapshot();
  saveState.value = 'saved';
};

const loadOptions = async company => {
  if (!company || options.value.company === company) return;
  try {
    const { data } = await ErpAPI.orderOptions(
      company,
      draft.value?.kind || 'fresh'
    );
    options.value = { ...data, company };
  } catch (error) {
    options.value = { company };
    useAlert(orderErrorMessage(t, error));
  }
};

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

const finishSubmit = data => {
  fill(data);
  emit('changed', data);
  if (data.status === 'created')
    useAlert(
      t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.RECORDED_DONE', {
        number: data.erp_number,
      })
    );
};

// a gravação roda no Sidekiq: confere a cada 2 s até sair de "submitting" (ou parar no meio)
const poll = () => {
  stopPolling();
  pollTimer = setTimeout(async () => {
    polls += 1;
    try {
      const { data } = await ErpAPI.orderDraft(draft.value.id);
      if (data.draft.status !== 'submitting' || data.draft.stuck) {
        finishSubmit(data.draft);
        return;
      }
    } catch {
      // rede caiu: tenta de novo no próximo ciclo
    }
    if (isOpen.value && polls < POLL_LIMIT) poll();
  }, POLL_EVERY);
};

const persist = async body => {
  saveState.value = 'saving';
  try {
    const { data } = await ErpAPI.saveOrderDraft(draft.value.id, body);
    // os campos da tela ficam: a pessoa pode ter digitado mais enquanto salvava
    draft.value = { ...data.draft, fields: fields.value };
    saveState.value = snapshot() === saved ? 'saved' : 'pending';
    emit('changed', data.draft);
  } catch (error) {
    saved = '';
    saveState.value = 'error';
    useAlert(orderErrorMessage(t, error));
  }
};

// uma gravação por vez, na ordem
const queue = body => {
  chain = chain.then(() => persist(body));
  return chain;
};

const saveNow = () => {
  clearTimeout(saveTimer);
  if (!canEdit.value) return chain;
  const current = snapshot();
  if (current === saved) return chain;
  saved = current;
  return queue(payload());
};

watch(
  [fields, items],
  () => {
    if (!canEdit.value || snapshot() === saved) return;
    saveState.value = 'pending';
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, SAVE_DELAY);
  },
  { deep: true }
);

// ---- cliente: primeiro a unidade (só as liberadas para OS), depois o cliente dela ----
const orderCompanies = computed(() => erpState.orderCompanies || []);
const initials = computed(() =>
  String(draft.value?.customer_name || '?')
    .split(/\s+/)
    .slice(0, 2)
    .map(word => word[0])
    .join('')
    .toUpperCase()
);

const startPicking = () => {
  pickCompany.value =
    draft.value.company && orderCompanies.value.includes(draft.value.company)
      ? draft.value.company
      : orderCompanies.value[0] || '';
  pending.value = null;
  picking.value = !picking.value;
};

const searchCustomers = async q => {
  if (!pickCompany.value) return [];
  const { data } = await withLoadingRetry(() =>
    ErpAPI.customers(
      q,
      q ? null : props.contactId || draft.value?.contact_id,
      pickCompany.value
    )
  );
  return (data.customers || []).filter(
    row => row.empresa === pickCompany.value
  );
};

// troca de cliente vai na hora: a máquina escolhida sai (é do cliente) e, em outra unidade, os itens também
const applyCustomer = async (row, clearItems = false) => {
  clearTimeout(saveTimer);
  pending.value = null;
  picking.value = false;
  fields.value = {
    ...fields.value,
    maquina: null,
    maquina_descricao: null,
    serie: null,
    horimetro: null,
    maquina_do_cliente: true,
  };
  if (clearItems) items.value = [];
  draft.value = {
    ...draft.value,
    company: row.empresa,
    customer_code: row.codigo,
    customer_name: row.nome,
  };
  saved = snapshot();
  await queue({
    company: row.empresa,
    customer_code: row.codigo,
    customer_name: row.nome,
    ...payload(),
  });
  await loadOptions(row.empresa);
  nextTick(() => itemsRef.value?.focusSearch());
};

const chooseCustomer = row => {
  if (row.empresa !== draft.value.company && items.value.length) {
    pending.value = row;
    return;
  }
  applyCustomer(row);
};

// ---- abrir, gravar, descartar, cancelar ----
const open = async (draftOrId, { focus = false } = {}) => {
  stopPolling();
  confirmDelete.value = false;
  confirmCancel.value = false;
  picking.value = false;
  options.value = {};
  isOpen.value = true;
  loading.value = true;
  try {
    let data = draftOrId;
    if (typeof draftOrId !== 'object' || !draftOrId.fields) {
      const response = await ErpAPI.orderDraft(draftOrId?.id || draftOrId);
      data = response.data.draft;
    }
    fill(data);
    if (!isRecorded.value) await loadOptions(data.company);
    if (data.status === 'submitting' && !data.stuck) {
      polls = 0;
      poll();
    }
    if (canEdit.value && !data.customer_code) startPicking();
    else if (focus) nextTick(() => itemsRef.value?.focusSearch());
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
    isOpen.value = false;
  } finally {
    loading.value = false;
  }
};

const close = async () => {
  stopPolling();
  await saveNow();
  isOpen.value = false;
};

const submit = async () => {
  await saveNow();
  if (saveState.value === 'error') return;
  busy.value = 'submit';
  try {
    const { data } = await ErpAPI.submitOrderDraft(draft.value.id);
    if (data.draft.status === 'submitting') {
      fill(data.draft);
      emit('changed', data.draft);
      polls = 0;
      poll();
    } else {
      finishSubmit(data.draft);
    }
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const remove = async () => {
  if (!confirmDelete.value) {
    confirmDelete.value = true;
    return;
  }
  clearTimeout(saveTimer);
  busy.value = 'delete';
  try {
    await ErpAPI.deleteOrderDraft(draft.value.id);
    emit('removed', draft.value.id);
    isOpen.value = false;
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
    confirmDelete.value = false;
  }
};

// muda a situação da OS para CANCELADA pelas rotas do quadro de OS; nada é apagado
const cancelOs = async () => {
  if (!confirmCancel.value) {
    confirmCancel.value = true;
    return;
  }
  busy.value = 'cancel';
  try {
    const { data } = await ErpAPI.cancelOrderOs(draft.value.id);
    fill(data.draft);
    emit('changed', data.draft);
    useAlert(
      t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.CANCELLED', {
        number: data.draft.erp_number,
      })
    );
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
    confirmCancel.value = false;
  }
};

const goToErp = async () => {
  const target = erpLink.value;
  await close();
  router.push(target);
};

const onKey = event => {
  if (event.key === 'Escape' && !event.defaultPrevented) close();
};

onBeforeUnmount(() => {
  stopPolling();
  saveNow();
});

const LABEL =
  'flex flex-col gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10';
const SELECT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand normal-case !pr-7 bg-[right_-1.25rem_center]';

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[9999] flex justify-end bg-n-alpha-black1 backdrop-blur-[1px]"
      @keydown="onKey"
      @click.self="close"
    >
      <section
        class="flex flex-col w-full h-full shadow-xl sm:max-w-[min(72rem,calc(100%_-_3rem))] bg-n-solid-2 outline outline-1 outline-n-container"
        role="dialog"
        aria-modal="true"
        :aria-label="title"
        tabindex="-1"
        data-erp-order-drawer
      >
        <header
          class="flex items-start gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak"
        >
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
                {{ title }}
              </h3>
              <template v-if="draft">
                <span
                  v-if="canEdit"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full"
                  :class="
                    saveState === 'error'
                      ? 'bg-n-ruby-3 text-n-ruby-11'
                      : 'bg-n-alpha-2 text-n-slate-11'
                  "
                >
                  <Icon
                    v-if="saveState === 'saved'"
                    icon="i-lucide-check"
                    class="size-3"
                  />
                  {{ t(`OUTSIDER_ERP.BUDGET.SAVE.${saveState.toUpperCase()}`) }}
                  <button
                    v-if="saveState === 'error'"
                    type="button"
                    class="underline"
                    @click="saveNow"
                  >
                    {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
                  </button>
                </span>
                <span
                  v-else-if="chip"
                  class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-full"
                  :class="chip.class"
                >
                  <Spinner v-if="chip.spinner" class="size-3" />
                  {{ chip.text }}
                </span>
              </template>
            </div>
            <span v-if="draft" class="text-xs truncate text-n-slate-10">
              {{
                draft.customer_code || isRecorded
                  ? t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.GOES_TO', {
                      company: companyName(draft.company),
                    })
                  : t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.GOES_TO_PICK')
              }}
            </span>
          </div>
          <Button
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('OUTSIDER_ERP.CANCEL')"
            @click="close"
          />
        </header>

        <div v-if="loading" class="flex items-center justify-center flex-1">
          <Spinner class="text-n-slate-10" />
        </div>

        <template v-else-if="draft">
          <!-- gravada: número oficial e o que foi conferido no ERP -->
          <template v-if="isRecorded">
            <div class="flex-1 min-h-0 px-4 py-4 overflow-y-auto sm:px-6">
              <ErpOrderResult :draft="draft" />
              <p
                v-if="confirmCancel"
                class="p-3 mt-4 mb-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
              >
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.CANCEL_CONFIRM_HINT') }}
              </p>
            </div>
            <footer
              class="flex flex-wrap items-center gap-2 px-4 py-3 border-t sm:px-6 border-n-weak"
            >
              <span class="flex-1 min-w-[10rem] text-xs text-n-slate-10">
                {{
                  t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.BY', {
                    name: draft.user?.name || '—',
                    date: formatDate(draft.erp_created_at),
                  })
                }}
              </span>
              <Button
                v-if="draft.can_cancel"
                size="sm"
                variant="faded"
                color="ruby"
                icon="i-lucide-ban"
                :label="
                  confirmCancel
                    ? t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.CONFIRM_CANCEL_OS')
                    : t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.CANCEL_OS')
                "
                :is-loading="busy === 'cancel'"
                data-erp-order-cancel
                @click="cancelOs"
              />
              <Button
                v-if="erpLink"
                size="sm"
                variant="faded"
                color="slate"
                icon="i-lucide-arrow-up-right"
                :label="t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.VIEW_IN_ERP')"
                @click="goToErp"
              />
              <Button
                size="sm"
                :label="t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.CLOSE')"
                @click="close"
              />
            </footer>
          </template>

          <!-- rascunho (ou gravação em andamento) -->
          <template v-else>
            <div class="flex-1 min-h-0 px-4 py-4 overflow-y-auto sm:px-6">
              <div class="flex flex-col gap-4">
                <p
                  v-if="status === 'draft' && !draft.can_edit"
                  class="flex items-center gap-2 p-3 mb-0 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
                >
                  <Icon icon="i-lucide-lock" class="size-4 shrink-0" />
                  {{
                    t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.READ_ONLY', {
                      user: draft.user?.name || '—',
                    })
                  }}
                </p>
                <p
                  v-if="errorText && !isSubmitting"
                  class="flex items-start gap-2 p-3 mb-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
                  data-erp-order-error
                >
                  <Icon
                    icon="i-lucide-circle-alert"
                    class="mt-0.5 size-4 shrink-0"
                  />
                  <span>
                    {{ t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.NOT_RECORDED') }}
                    {{
                      failedCheck
                        ? orderReasonText(
                            t,
                            failedCheck.key,
                            failedCheck.detail
                          )
                        : errorText
                    }}
                  </span>
                </p>
                <p
                  v-if="draft.erp_number"
                  class="p-3 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
                >
                  {{
                    t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.HALF_DONE', {
                      number: draft.erp_number,
                    })
                  }}
                </p>

                <ErpOrderFields
                  v-model="fields"
                  :company="draft.company"
                  :customer="draft.customer_code"
                  :options="options"
                  :read-only="!canEdit"
                  :missing="missing"
                >
                  <template #customer>
                    <div class="flex flex-col gap-1">
                      <span :class="LABEL">
                        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.CUSTOMER') }}
                      </span>
                      <div
                        class="flex items-center gap-3 px-3 py-1.5 border rounded-xl border-n-weak bg-n-alpha-1"
                      >
                        <span
                          class="flex items-center justify-center text-sm font-semibold rounded-lg shrink-0 size-8 bg-n-teal-3 text-n-teal-11"
                        >
                          {{ initials }}
                        </span>
                        <div class="flex flex-col flex-1 min-w-0">
                          <span
                            v-if="draft.customer_code"
                            class="text-sm font-semibold truncate text-n-slate-12"
                          >
                            {{ draft.customer_code }} ·
                            {{ draft.customer_name }}
                          </span>
                          <span
                            v-else
                            class="text-sm font-medium text-n-amber-11"
                          >
                            {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.NONE') }}
                          </span>
                          <span
                            v-if="draft.customer_code"
                            class="text-xs truncate text-n-slate-10"
                          >
                            {{
                              t('OUTSIDER_ERP.BUDGET.CUSTOMER.UNIT', {
                                company: companyName(draft.company),
                              })
                            }}
                          </span>
                        </div>
                        <button
                          v-if="canEdit"
                          type="button"
                          class="text-sm font-medium shrink-0 text-n-brand hover:underline"
                          @click="startPicking"
                        >
                          {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.CHANGE') }}
                        </button>
                      </div>
                    </div>
                  </template>
                </ErpOrderFields>

                <div v-if="picking" class="flex flex-col gap-2">
                  <div
                    class="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]"
                  >
                    <label :class="LABEL">
                      {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.STEP_UNIT') }}
                      <select v-model="pickCompany" :class="SELECT">
                        <option
                          v-for="db in orderCompanies"
                          :key="db"
                          :value="db"
                        >
                          {{ companyName(db) }}
                        </option>
                      </select>
                    </label>
                    <div class="flex flex-col min-w-0 gap-1">
                      <span :class="LABEL">
                        {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.STEP_CUSTOMER') }}
                      </span>
                      <ErpPicker
                        v-if="pickCompany"
                        :source="pickCompany"
                        :search="searchCustomers"
                        :row-key="row => `${row.empresa}:${row.codigo}`"
                        :placeholder="
                          t('OUTSIDER_ERP.CONTACT.FILTER_PLACEHOLDER')
                        "
                        :empty-text="t('OUTSIDER_ERP.CONTACT.NO_RESULTS')"
                        @select="chooseCustomer"
                      >
                        <template #row="{ row }">
                          <span
                            class="text-xs font-medium truncate text-n-slate-12"
                          >
                            {{ row.nome }}
                          </span>
                          <span class="text-xs truncate text-n-slate-10">
                            {{
                              [
                                `#${row.codigo}`,
                                row.fantasia,
                                row.cidade &&
                                  [row.cidade, row.uf]
                                    .filter(Boolean)
                                    .join('/'),
                                row.documento,
                              ]
                                .filter(Boolean)
                                .join(' · ')
                            }}
                          </span>
                        </template>
                      </ErpPicker>
                    </div>
                  </div>
                  <div
                    v-if="pending"
                    class="flex flex-wrap items-center gap-3 p-3 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
                  >
                    <Icon
                      icon="i-lucide-triangle-alert"
                      class="size-4 shrink-0"
                    />
                    <span class="flex-1 min-w-[12rem]">
                      {{
                        t('OUTSIDER_ERP.BUDGET.CUSTOMER.OTHER_UNIT', {
                          company: companyName(pending.empresa),
                        })
                      }}
                    </span>
                    <button
                      type="button"
                      class="font-medium underline"
                      @click="applyCustomer(pending, true)"
                    >
                      {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.OTHER_UNIT_OK') }}
                    </button>
                    <button
                      type="button"
                      class="underline"
                      @click="pending = null"
                    >
                      {{ t('OUTSIDER_ERP.CANCEL') }}
                    </button>
                  </div>
                </div>

                <section class="flex flex-col gap-2">
                  <div
                    class="flex flex-wrap items-baseline justify-between gap-2"
                  >
                    <h4
                      class="mb-0 text-[11px] font-medium tracking-wide uppercase text-n-slate-10"
                    >
                      {{ t('OUTSIDER_ERP.ORDER_DRAFT.ITEMS.TITLE') }}
                    </h4>
                    <span v-if="canEdit" class="text-xs text-n-slate-10">
                      {{ t('OUTSIDER_ERP.ORDER_DRAFT.ITEMS.HINT') }}
                    </span>
                  </div>
                  <ErpBudgetItems
                    v-if="draft.customer_code"
                    ref="itemsRef"
                    v-model="items"
                    :company="draft.company"
                    :read-only="!canEdit"
                    :discount="false"
                  />
                  <p v-else class="mb-0 text-sm text-n-slate-10">
                    {{ t('OUTSIDER_ERP.ORDER_DRAFT.ITEMS.CUSTOMER_FIRST') }}
                  </p>
                </section>

                <div
                  class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]"
                >
                  <div class="flex flex-col gap-2 text-sm">
                    <label
                      class="flex items-center gap-2 text-n-slate-12"
                      :class="{ 'opacity-70': !canEdit }"
                    >
                      <input
                        :checked="fields.agendar === true"
                        type="checkbox"
                        :disabled="!canEdit"
                        @change="
                          fields = { ...fields, agendar: $event.target.checked }
                        "
                      />
                      {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.SCHEDULE') }}
                    </label>
                    <p
                      v-if="erpUser"
                      class="mb-0 text-xs text-n-slate-11"
                      data-erp-order-user
                    >
                      {{
                        t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.WILL_RECORD_AS', {
                          name: erpUser.nome || `#${erpUser.codigo}`,
                          code: erpUser.codigo,
                        })
                      }}
                    </p>
                    <p
                      v-else-if="options.company"
                      class="flex items-start gap-1.5 mb-0 text-xs text-n-amber-11"
                    >
                      <Icon
                        icon="i-lucide-triangle-alert"
                        class="size-3.5 shrink-0 mt-px"
                      />
                      {{ orderReasonText(t, 'usuario_erp') }}
                    </p>
                  </div>
                  <div
                    class="flex flex-col gap-1.5 p-4 text-sm border rounded-xl border-n-weak bg-n-alpha-1"
                  >
                    <div class="flex justify-between text-n-slate-11">
                      <span>{{
                        t('OUTSIDER_ERP.ORDER_DRAFT.TOTALS.PARTS')
                      }}</span>
                      <span class="tabular-nums">{{
                        formatMoney(totals.parts)
                      }}</span>
                    </div>
                    <div class="flex justify-between text-n-slate-11">
                      <span>{{
                        t('OUTSIDER_ERP.ORDER_DRAFT.TOTALS.SERVICES')
                      }}</span>
                      <span class="tabular-nums">{{
                        formatMoney(totals.services)
                      }}</span>
                    </div>
                    <div
                      class="flex justify-between pt-1.5 mt-0.5 font-semibold border-t border-n-weak text-[15px] text-n-slate-12"
                    >
                      <span>{{
                        t('OUTSIDER_ERP.ORDER_DRAFT.TOTALS.TOTAL')
                      }}</span>
                      <span class="tabular-nums">{{
                        formatMoney(totals.total)
                      }}</span>
                    </div>
                    <span class="text-xs text-n-slate-10">
                      {{ t('OUTSIDER_ERP.ORDER_DRAFT.TOTALS.HINT') }}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <footer
              class="flex flex-wrap items-center gap-2 px-4 py-3 border-t sm:px-6 border-n-weak"
            >
              <span class="flex-1 min-w-[10rem] text-xs text-n-slate-10">
                <template v-if="isSubmitting">
                  {{ t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.SUBMITTING_HINT') }}
                </template>
                <template v-else-if="!erpState.canCreateOrder">
                  {{ orderReasonText(t, 'order_write_disabled') }}
                </template>
                <template v-else-if="missing">
                  {{ orderReasonText(t, missing) }}
                </template>
                <template v-else>
                  {{
                    t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.FOOTER', {
                      count: items.length,
                    })
                  }}
                </template>
              </span>
              <Button
                v-if="canEdit"
                size="sm"
                variant="ghost"
                color="ruby"
                icon="i-lucide-trash-2"
                :label="
                  confirmDelete
                    ? t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.CONFIRM_DELETE')
                    : t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.DELETE')
                "
                :is-loading="busy === 'delete'"
                @click="remove"
                @blur="confirmDelete = false"
              />
              <Button
                v-if="draft.can_cancel && draft.erp_number"
                size="sm"
                variant="ghost"
                color="ruby"
                icon="i-lucide-ban"
                :label="
                  confirmCancel
                    ? t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.CONFIRM_CANCEL_OS')
                    : t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.CANCEL_OS')
                "
                :is-loading="busy === 'cancel'"
                @click="cancelOs"
                @blur="confirmCancel = false"
              />
              <Button
                v-if="status === 'draft' || draft.stuck"
                size="sm"
                icon="i-lucide-cloud-upload"
                :label="
                  draft.erp_number || draft.stuck
                    ? t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.SUBMIT_AGAIN')
                    : t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.SUBMIT')
                "
                :is-loading="busy === 'submit'"
                :disabled="
                  !erpState.canCreateOrder ||
                  !draft.can_submit ||
                  !!missing ||
                  saveState === 'saving'
                "
                data-erp-order-submit
                @click="submit"
              />
            </footer>
          </template>
        </template>
      </section>
    </div>
  </Teleport>
</template>
