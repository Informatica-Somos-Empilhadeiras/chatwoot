<script setup>
// OUTSIDER: gaveta do orçamento de peças e serviços (Outsider::Erp::Budget). Rascunho: o formulário (ErpBudgetForm)
// salva sozinho a cada mudança; "Ver PDF" mostra a prévia e "Gravar no ERP" manda para o Mais Prático (o servidor
// grava no Sidekiq e a gaveta acompanha). Gravado: o PDF oficial e o envio por WhatsApp/e-mail (ErpBudgetSend).
// Edição de um orçamento já gravado (status "revising", aberta pela seção ERP): o mesmo formulário, com cliente,
// pagamento e frete travados; "Salvar no ERP" regrava as linhas e "Descartar" volta como estava.
import { ref, computed, watch, nextTick, provide, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpBudgetForm from './ErpBudgetForm.vue';
import ErpBudgetSend from './ErpBudgetSend.vue';
import ErpPdfDialog from './ErpPdfDialog.vue';
import ErpDiscountApproval from './ErpDiscountApproval.vue';
import { quoteClass, companyName } from '../erpStore';
import { budgetErrorMessage, reasonText } from './budgetHelpers';

const props = defineProps({
  contactId: { type: Number, default: null },
  conversationId: { type: [Number, String], default: null },
  opportunityId: { type: Number, default: null },
});

const emit = defineEmits(['changed', 'removed']);

const { t } = useI18n();
const isOpen = ref(false);
const loading = ref(false);
const budget = ref(null);
const terms = ref({});
const items = ref([]);
const options = ref({});
// saved | pending | saving | error
const saveState = ref('saved');
const busy = ref('');
const confirmDelete = ref(false);
const erpStatus = ref('');
const formRef = ref(null);
const pdfRef = ref(null);

const SAVE_DELAY = 800;
const POLL_EVERY = 2000;
const POLL_LIMIT = 120;
let saveTimer = null;
let pollTimer = null;
let polls = 0;
let chain = Promise.resolve();
let saved = '';

const status = computed(() => budget.value?.status);
const isDraft = computed(() => status.value === 'draft');
const isSubmitting = computed(() => status.value === 'submitting');
const isRevising = computed(
  () =>
    status.value === 'revising' ||
    (isSubmitting.value && !!budget.value?.revision)
);
// na edição de um orçamento gravado ficam como no ERP (só a função de criar recebe)
const REVISION_LOCKED = [
  'customer',
  'pedido_cliente',
  'forma_pagto',
  'genero',
  'tipo_frete',
  'frete_valor',
];
const locked = computed(() => (isRevising.value ? REVISION_LOCKED : []));
const isRecorded = computed(() =>
  ['created', 'imported'].includes(status.value)
);
const canEdit = computed(
  () =>
    (isDraft.value && budget.value?.can_edit && !budget.value?.erp_number) ||
    (status.value === 'revising' && budget.value?.can_edit)
);
const canCreate = computed(() => options.value.can_create !== false);
const title = computed(() => {
  if (isRevising.value)
    return t('OUTSIDER_ERP.BUDGET.DRAWER.REVISING', {
      number: budget.value.erp_number,
    });
  if (isRecorded.value)
    return t('OUTSIDER_ERP.BUDGET.DRAWER.RECORDED', {
      number: budget.value.erp_number,
    });
  return t('OUTSIDER_ERP.BUDGET.DRAWER.NEW');
});
// desconto acima do limite (estado do rascunho salvo, ver Outsider::Erp::DiscountPolicy)
const discount = computed(() => budget.value?.discount || {});
const discountBlocked = computed(
  () => discount.value.needs_approval && !discount.value.approved
);
// o que falta para gravar (o servidor confere de novo)
const missing = computed(() => {
  if (!budget.value) return '';
  if (isRevising.value) {
    if (!items.value.length) return 'sem_itens';
    return discountBlocked.value ? 'desconto_sem_liberacao' : '';
  }
  if (!budget.value.customer_code) return 'sem_cliente';
  if (!items.value.length) return 'sem_itens';
  if (!Number(terms.value.forma_pagto)) return 'forma_pagto';
  if (!Number(terms.value.vendedor)) return 'vendedor';
  if (discountBlocked.value && !budget.value.erp_number)
    return 'desconto_sem_liberacao';
  return '';
});
const errorText = computed(() => reasonText(t, budget.value?.error));
// o que o ERP deixou de fora: { codigo, descricao, motivo } -> "1180 RODA DE CARGA"
const skipped = computed(() =>
  (budget.value?.skipped || []).map(item =>
    typeof item === 'object'
      ? [item.codigo, item.descricao].filter(Boolean).join(' ')
      : String(item)
  )
);

const plainItems = list => list.map(({ total, ...item }) => item);
const snapshot = () =>
  JSON.stringify({ terms: terms.value, items: plainItems(items.value) });

const fill = data => {
  budget.value = data;
  terms.value = { ...(data.terms || {}) };
  items.value = plainItems(data.items || []);
  saved = snapshot();
  saveState.value = 'saved';
};

const loadOptions = async company => {
  if (!company || options.value.company === company) return;
  try {
    const { data } = await ErpAPI.budgetOptions(company);
    options.value = { ...data, company };
  } catch {
    // listas fora do ar: os campos viram código digitado
    options.value = { company };
  }
};

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

const finishSubmit = data => {
  const wasRevision = !!budget.value?.revision;
  fill(data);
  emit('changed', data);
  if (wasRevision && !data.revision)
    useAlert(
      t('OUTSIDER_ERP.BUDGET.DRAWER.REVISED_DONE', {
        number: data.erp_number,
      })
    );
  else if (data.status === 'created')
    useAlert(
      t('OUTSIDER_ERP.BUDGET.DRAWER.RECORDED_DONE', {
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
      const { data } = await ErpAPI.budget(budget.value.id);
      if (data.budget.status !== 'submitting' || data.budget.stuck) {
        finishSubmit(data.budget);
        return;
      }
    } catch {
      // rede caiu: tenta de novo no próximo ciclo
    }
    if (isOpen.value && polls < POLL_LIMIT) poll();
  }, POLL_EVERY);
};

const persist = async payload => {
  saveState.value = 'saving';
  try {
    const { data } = await ErpAPI.saveBudget(budget.value.id, payload);
    // terms/items da tela ficam: a pessoa pode ter digitado mais enquanto salvava
    budget.value = data.budget;
    saveState.value = snapshot() === saved ? 'saved' : 'pending';
    emit('changed', data.budget);
  } catch (error) {
    saved = '';
    saveState.value = 'error';
    useAlert(budgetErrorMessage(t, error));
  }
};

// uma gravação por vez, na ordem
const queue = payload => {
  chain = chain.then(() => persist(payload));
  return chain;
};

const saveNow = () => {
  clearTimeout(saveTimer);
  if (!canEdit.value) return chain;
  const current = snapshot();
  if (current === saved) return chain;
  saved = current;
  return queue({ terms: terms.value, items: plainItems(items.value) });
};

watch(
  [terms, items],
  () => {
    if (!canEdit.value || snapshot() === saved) return;
    saveState.value = 'pending';
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, SAVE_DELAY);
  },
  { deep: true }
);

// troca de cliente vai na hora (junto com o resto), e a unidade nova traz as listas dela
const changeCustomer = async payload => {
  clearTimeout(saveTimer);
  if (payload.items) items.value = [];
  budget.value = { ...budget.value, ...payload };
  saved = snapshot();
  await queue({
    ...payload,
    terms: terms.value,
    items: plainItems(items.value),
  });
  await loadOptions(budget.value.company);
  nextTick(() => formRef.value?.focusSearch());
};

const open = async (budgetOrId, { focus = false } = {}) => {
  stopPolling();
  confirmDelete.value = false;
  erpStatus.value = '';
  isOpen.value = true;
  loading.value = true;
  try {
    let data = budgetOrId;
    if (typeof budgetOrId !== 'object' || !budgetOrId.terms) {
      const response = await ErpAPI.budget(budgetOrId?.id || budgetOrId);
      data = response.data.budget;
    }
    fill(data);
    await loadOptions(data.company);
    if (data.status === 'submitting' && !data.stuck) {
      polls = 0;
      poll();
    }
    if (focus && data.customer_code)
      nextTick(() => formRef.value?.focusSearch());
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
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
    const { data } = await ErpAPI.submitBudget(budget.value.id);
    if (data.budget.status === 'submitting') {
      budget.value = data.budget;
      emit('changed', data.budget);
      polls = 0;
      poll();
    } else {
      finishSubmit(data.budget);
    }
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

// código e senha de quem libera: vai direto para o servidor, que confere no ERP; nada fica guardado aqui
const approve = async payload => {
  await saveNow();
  busy.value = 'approve';
  try {
    const { data } = await ErpAPI.approveDiscount(budget.value.id, payload);
    budget.value = data.budget;
    emit('changed', data.budget);
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
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
    await ErpAPI.deleteBudget(budget.value.id);
    emit('removed', budget.value.id);
    isOpen.value = false;
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
    confirmDelete.value = false;
  }
};

// descarta a edição do orçamento gravado: nada foi para o ERP
const discard = async () => {
  clearTimeout(saveTimer);
  busy.value = 'discard';
  try {
    await chain;
    const { data } = await ErpAPI.cancelRevision(budget.value.id);
    fill(data.budget);
    emit('changed', data.budget);
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const showPdf = async () => {
  await saveNow();
  pdfRef.value?.open(budget.value.id);
};

// rascunho novo com o mesmo cliente, itens e condições: abre aqui mesmo
const copy = async () => {
  busy.value = 'copy';
  try {
    const { data } = await ErpAPI.copyBudget(budget.value.id, {
      contact_id: props.contactId || undefined,
      conversation_id: props.conversationId || undefined,
      opportunity_id: props.opportunityId || undefined,
    });
    emit('changed', data.budget);
    await open(data.budget, { focus: true });
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const sent = data => {
  budget.value = data;
  emit('changed', data);
};

// fotos dos produtos (ErpProductSearch): vão na conversa do chat de onde abriu ou na aberta do cliente no WhatsApp
provide(
  'erpPhotoTarget',
  computed(() => ({
    conversationId: props.conversationId,
    contactId: budget.value?.contact_id || props.contactId,
  }))
);

const onKey = event => {
  if (
    event.key === 'Escape' &&
    !event.defaultPrevented &&
    !pdfRef.value?.isOpen
  )
    close();
};

onBeforeUnmount(() => {
  stopPolling();
  saveNow();
});

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
      >
        <header
          class="flex items-start gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak"
        >
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
                {{ title }}
              </h3>
              <template v-if="budget">
                <span
                  v-if="isRecorded && erpStatus"
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="quoteClass(erpStatus)"
                >
                  {{ erpStatus }}
                </span>
                <span
                  v-else-if="isSubmitting && !budget.stuck"
                  class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-full bg-n-blue-3 text-n-blue-11"
                >
                  <Spinner class="size-3" />
                  {{ t('OUTSIDER_ERP.BUDGET.DRAWER.SUBMITTING') }}
                </span>
                <span
                  v-else-if="canEdit"
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
              </template>
            </div>
            <span v-if="budget" class="text-xs truncate text-n-slate-10">
              {{
                isRecorded
                  ? t('OUTSIDER_ERP.BUDGET.DRAWER.RECORDED_SUB', {
                      company: companyName(budget.company),
                      customer: budget.customer_name || budget.customer_code,
                    })
                  : budget.customer_code
                    ? t('OUTSIDER_ERP.BUDGET.DRAWER.GOES_TO', {
                        company: companyName(budget.company),
                      })
                    : t('OUTSIDER_ERP.BUDGET.DRAWER.GOES_TO_PICK')
              }}
            </span>
          </div>
          <template v-if="isRecorded">
            <Button
              size="sm"
              variant="faded"
              color="slate"
              icon="i-lucide-copy"
              :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.COPY')"
              :is-loading="busy === 'copy'"
              @click="copy"
            />
          </template>
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

        <template v-else-if="budget">
          <!-- gravado: PDF oficial e envio -->
          <div
            v-if="isRecorded"
            class="flex flex-col flex-1 min-h-0 gap-3 p-4 overflow-y-auto sm:p-6 lg:overflow-hidden"
          >
            <p
              v-if="skipped.length"
              class="flex items-start gap-2 p-3 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
            >
              <Icon
                icon="i-lucide-triangle-alert"
                class="mt-0.5 size-4 shrink-0"
              />
              <span>
                {{
                  t('OUTSIDER_ERP.BUDGET.DRAWER.SKIPPED', {
                    items: skipped.join(', '),
                  })
                }}
              </span>
            </p>
            <p
              v-if="budget.conditions_error"
              class="p-3 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
            >
              {{ t('OUTSIDER_ERP.BUDGET.DRAWER.CONDITIONS_ERROR') }}
            </p>
            <ErpBudgetSend
              :key="budget.id"
              class="flex-1 min-h-0"
              :budget="budget"
              @sent="sent"
              @meta="meta => (erpStatus = meta.status || '')"
            />
          </div>

          <!-- rascunho (ou gravação em andamento) -->
          <template v-else>
            <div class="flex-1 min-h-0 px-4 py-4 overflow-y-auto sm:px-6">
              <div class="flex flex-col gap-3">
                <p
                  v-if="isRevising"
                  class="flex items-start gap-2 p-3 mb-0 text-sm rounded-lg bg-n-blue-2 text-n-blue-11"
                >
                  <Icon icon="i-lucide-pencil" class="mt-0.5 size-4 shrink-0" />
                  <span>
                    {{
                      budget.can_edit
                        ? t('OUTSIDER_ERP.BUDGET.DRAWER.REVISING_HINT', {
                            number: budget.erp_number,
                          })
                        : t('OUTSIDER_ERP.BUDGET.DRAWER.REVISING_OTHER', {
                            user: budget.revision?.name || '—',
                          })
                    }}
                  </span>
                </p>
                <p
                  v-if="isDraft && !budget.can_edit"
                  class="flex items-center gap-2 p-3 mb-0 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
                >
                  <Icon icon="i-lucide-lock" class="size-4 shrink-0" />
                  {{
                    t('OUTSIDER_ERP.BUDGET.DRAWER.READ_ONLY', {
                      user: budget.user?.name || '—',
                    })
                  }}
                </p>
                <p
                  v-if="errorText && !isSubmitting"
                  class="flex items-start gap-2 p-3 mb-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
                >
                  <Icon
                    icon="i-lucide-circle-alert"
                    class="mt-0.5 size-4 shrink-0"
                  />
                  <span>
                    {{ t('OUTSIDER_ERP.BUDGET.DRAWER.NOT_RECORDED') }}
                    {{ errorText }}
                  </span>
                </p>
                <p
                  v-if="budget.erp_number && !isRecorded && !isRevising"
                  class="p-3 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
                >
                  {{
                    t('OUTSIDER_ERP.BUDGET.DRAWER.HALF_DONE', {
                      number: budget.erp_number,
                    })
                  }}
                </p>
                <ErpBudgetForm
                  ref="formRef"
                  v-model:terms="terms"
                  v-model:items="items"
                  :budget="budget"
                  :options="options"
                  :contact-id="contactId"
                  :read-only="!canEdit"
                  :locked="locked"
                  @customer="changeCustomer"
                />
              </div>
            </div>

            <div
              v-if="
                discount.needs_approval && (!budget.erp_number || isRevising)
              "
              class="px-4 pt-3 border-t sm:px-6 border-n-weak"
            >
              <ErpDiscountApproval
                :discount="discount"
                :busy="busy === 'approve'"
                :pending="saveState !== 'saved'"
                :read-only="!canEdit"
                @approve="approve"
              />
            </div>
            <footer
              class="flex flex-wrap items-center gap-2 px-4 py-3 sm:px-6"
              :class="{
                'border-t border-n-weak':
                  !discount.needs_approval ||
                  (budget.erp_number && !isRevising),
              }"
            >
              <span class="flex-1 min-w-[10rem] text-xs text-n-slate-10">
                <template v-if="isSubmitting && !budget.stuck">
                  {{ t('OUTSIDER_ERP.BUDGET.DRAWER.SUBMITTING_HINT') }}
                </template>
                <template v-else-if="!canCreate">
                  {{ reasonText(t, 'quote_write_disabled') }}
                </template>
                <template v-else-if="canEdit && missing">
                  {{ reasonText(t, missing) }}
                </template>
                <template v-else>
                  {{
                    t('OUTSIDER_ERP.BUDGET.DRAWER.FOOTER', {
                      count: items.length,
                    })
                  }}
                </template>
              </span>
              <Button
                v-if="isRevising && budget.can_edit && !isSubmitting"
                size="sm"
                variant="ghost"
                color="slate"
                icon="i-lucide-undo-2"
                :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.DISCARD')"
                :is-loading="busy === 'discard'"
                @click="discard"
              />
              <Button
                v-if="canEdit && !isRevising"
                size="sm"
                variant="ghost"
                color="ruby"
                icon="i-lucide-trash-2"
                :label="
                  confirmDelete
                    ? t('OUTSIDER_ERP.BUDGET.ACTIONS.CONFIRM_DELETE')
                    : t('OUTSIDER_ERP.BUDGET.ACTIONS.DELETE')
                "
                :is-loading="busy === 'delete'"
                @click="remove"
                @blur="confirmDelete = false"
              />
              <Button
                size="sm"
                variant="faded"
                color="slate"
                icon="i-lucide-eye"
                :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.PDF')"
                :disabled="!items.length"
                @click="showPdf"
              />
              <Button
                v-if="isDraft || status === 'revising' || budget.stuck"
                size="sm"
                icon="i-lucide-cloud-upload"
                :label="
                  isRevising
                    ? t('OUTSIDER_ERP.BUDGET.ACTIONS.SAVE_REVISION')
                    : budget.erp_number || budget.stuck
                      ? t('OUTSIDER_ERP.BUDGET.ACTIONS.SUBMIT_AGAIN')
                      : t('OUTSIDER_ERP.BUDGET.ACTIONS.SUBMIT')
                "
                :is-loading="busy === 'submit'"
                :disabled="
                  !canCreate ||
                  !!missing ||
                  (!budget.can_edit && !budget.stuck) ||
                  saveState === 'saving'
                "
                @click="submit"
              />
            </footer>
          </template>
        </template>
      </section>
    </div>
    <ErpPdfDialog ref="pdfRef" />
  </Teleport>
</template>
