<script setup>
// OUTSIDER: "Converter orçamento em OS", como o desktop do Mais Prático: confere no ERP antes (orçamento em NEGOCIAÇÃO,
// sem OS, sem pedido, ninguém com ele aberto, permissão "Conversão OS" do seu usuário do ERP), pede o que o desktop pede
// (máquina, tipo de atendimento, técnico, previsão, entrega e classe) e converte: cliente, peças e valores vêm do
// orçamento, que fica FECHADO e ligado à OS (Outsider::Erp::Orders::Creator, no Sidekiq). Já convertido pelo chat: mostra
// a OS (ErpOrderResult). Parou no meio: "Tentar de novo" continua a mesma OS.
import { ref, computed, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpOrderFields from './ErpOrderFields.vue';
import ErpOrderResult from './ErpOrderResult.vue';
import { erpTabs } from '../sidebar';
import { ERP_ROUTE, companyName, formatMoney } from '../erpStore';
import {
  checkText,
  orderDraftsTick,
  orderErrorMessage,
  orderReasonText,
} from './orderHelpers';

const emit = defineEmits(['converted']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const isOpen = ref(false);
// loading | form | submitting | done
const phase = ref('loading');
const target = ref({});
const preview = ref(null);
const previewLoading = ref(false);
const options = ref({});
const draft = ref(null);
const fields = ref({});
const busy = ref('');
const confirmCancel = ref(false);

const POLL_EVERY = 2000;
const POLL_LIMIT = 120;
let pollTimer = null;
let polls = 0;

const DEFAULT_FIELDS = {
  maquina_do_cliente: true,
  maquina_parada: false,
  agendar: false,
  enviar_app: false,
};

const quote = computed(() => preview.value?.quote || {});
const customerCode = computed(
  () => quote.value.cliente || target.value.customerCode || null
);
const halfDone = computed(() => !!draft.value?.erp_number);
const checks = computed(() => preview.value?.checks || []);
const erpUser = computed(() => options.value.erp_user);
const draftError = computed(() => {
  if (!draft.value?.error) return '';
  const failed = (draft.value.checks || []).find(check => !check.ok);
  return failed
    ? orderReasonText(t, failed.key, failed.detail)
    : orderReasonText(t, draft.value.error);
});

// o que falta para converter (o servidor confere tudo de novo, no ERP, antes de gravar)
const missing = computed(() => {
  if (halfDone.value) return '';
  if (!preview.value) return 'loading';
  if (!preview.value.ok) return preview.value.error || 'orcamento';
  if (!erpUser.value) return 'usuario_erp';
  if (options.value.machine_required && !Number(fields.value.maquina))
    return 'maquina_obrigatoria';
  if (!fields.value.tipo_atendimento) return 'tipo_atendimento';
  if (!Number(fields.value.classe)) return 'classe';
  return '';
});
const footerText = computed(() => {
  if (phase.value === 'submitting')
    return t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.SUBMITTING_HINT');
  if (halfDone.value)
    return t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.HALF_DONE', {
      number: draft.value.erp_number,
    });
  if (missing.value === 'loading')
    return t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.CHECKING');
  if (missing.value) {
    // o detalhe vem da conferência que falhou (por exemplo, quem está com o orçamento aberto)
    const failed = checks.value.find(check => !check.ok);
    return orderReasonText(
      t,
      missing.value,
      failed?.key === missing.value ? failed.detail : ''
    );
  }
  return t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.FOOTER');
});

const erpLink = computed(() =>
  draft.value?.erp_number && erpTabs().some(item => item.name === 'os')
    ? {
        name: ERP_ROUTE,
        params: { accountId: route.params.accountId, tab: 'os' },
        query: { open: `${draft.value.company}:${draft.value.erp_number}` },
      }
    : null
);

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

const finish = data => {
  draft.value = data;
  if (data.status === 'created') {
    phase.value = 'done';
    orderDraftsTick.value += 1;
    emit('converted', data);
    useAlert(
      t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.DONE', {
        number: data.quote_number,
        os: data.erp_number,
      })
    );
  } else {
    phase.value = 'form';
  }
};

const poll = () => {
  stopPolling();
  pollTimer = setTimeout(async () => {
    polls += 1;
    try {
      const { data } = await ErpAPI.orderDraft(draft.value.id);
      if (data.draft.status !== 'submitting' || data.draft.stuck) {
        finish(data.draft);
        return;
      }
    } catch {
      // rede caiu: tenta de novo no próximo ciclo
    }
    if (isOpen.value && polls < POLL_LIMIT) poll();
  }, POLL_EVERY);
};

const loadPreview = async () => {
  previewLoading.value = true;
  try {
    const { data } = await ErpAPI.orderPreview(
      target.value.company,
      target.value.number
    );
    preview.value = data;
  } catch (error) {
    preview.value = { ok: false, error: orderErrorMessage(t, error) };
  } finally {
    previewLoading.value = false;
  }
};

const loadOptions = async () => {
  try {
    const { data } = await ErpAPI.orderOptions(
      target.value.company,
      'conversion'
    );
    options.value = data;
  } catch (error) {
    options.value = {};
    useAlert(orderErrorMessage(t, error));
  }
};

// { company, number, customerCode, customerName, contactId, conversationId }
const open = async params => {
  stopPolling();
  target.value = params;
  isOpen.value = true;
  phase.value = 'loading';
  preview.value = null;
  options.value = {};
  draft.value = null;
  confirmCancel.value = false;
  fields.value = { ...DEFAULT_FIELDS };
  try {
    const { data } = await ErpAPI.orderDrafts({
      company: params.company,
      quote_number: params.number,
    });
    const list = (data.drafts || []).filter(item => item.kind === 'conversion');
    const existing =
      list.find(item => item.status === 'created') ||
      list.find(item => item.status !== 'created');
    if (existing) {
      const response = await ErpAPI.orderDraft(existing.id);
      draft.value = response.data.draft;
      fields.value = { ...DEFAULT_FIELDS, ...(draft.value.fields || {}) };
    }
    if (draft.value?.status === 'created') {
      phase.value = 'done';
      return;
    }
    if (draft.value?.status === 'submitting' && !draft.value.stuck) {
      phase.value = 'submitting';
      polls = 0;
      poll();
      return;
    }
    phase.value = 'form';
    await Promise.all([loadPreview(), loadOptions()]);
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
    isOpen.value = false;
  }
};

const close = () => {
  stopPolling();
  isOpen.value = false;
};

const convert = async () => {
  busy.value = 'convert';
  try {
    if (!draft.value) {
      const { data } = await ErpAPI.createOrderDraft({
        kind: 'conversion',
        company: target.value.company,
        quote_number: target.value.number,
        contact_id: target.value.contactId || undefined,
        conversation_id: target.value.conversationId || undefined,
        customer_code: customerCode.value || undefined,
        customer_name: target.value.customerName || undefined,
      });
      draft.value = data.draft;
      if (data.draft.status === 'created') {
        finish(data.draft);
        return;
      }
    }
    if (!halfDone.value && draft.value.status === 'draft') {
      const { data } = await ErpAPI.saveOrderDraft(draft.value.id, {
        fields: fields.value,
      });
      draft.value = data.draft;
    }
    const { data } = await ErpAPI.submitOrderDraft(draft.value.id);
    draft.value = data.draft;
    if (data.draft.status === 'submitting') {
      phase.value = 'submitting';
      polls = 0;
      poll();
    } else {
      finish(data.draft);
    }
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const cancelOs = async () => {
  if (!confirmCancel.value) {
    confirmCancel.value = true;
    return;
  }
  busy.value = 'cancel';
  try {
    const { data } = await ErpAPI.cancelOrderOs(draft.value.id);
    draft.value = data.draft;
    orderDraftsTick.value += 1;
    emit('converted', data.draft);
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
    confirmCancel.value = false;
  }
};

const goToErp = () => {
  const link = erpLink.value;
  close();
  router.push(link);
};

onBeforeUnmount(stopPolling);

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[10000] flex items-start justify-center p-0 sm:p-6 bg-n-alpha-black1 backdrop-blur-[2px]"
      @keydown.esc="close"
      @click.self="close"
    >
      <section
        class="flex flex-col w-full h-full max-w-3xl overflow-hidden shadow-xl sm:h-auto sm:max-h-full sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
        role="dialog"
        aria-modal="true"
        tabindex="-1"
        data-erp-convert-dialog
      >
        <header
          class="flex items-start justify-between gap-3 px-5 py-4 border-b shrink-0 border-n-weak"
        >
          <div class="flex flex-col min-w-0 gap-0.5">
            <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
              {{
                t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.TITLE', {
                  number: target.number,
                })
              }}
            </h3>
            <span class="text-xs truncate text-n-slate-10">
              {{
                [
                  [customerCode, target.customerName]
                    .filter(Boolean)
                    .join(' · '),
                  t('OUTSIDER_ERP.BUDGET.CUSTOMER.UNIT', {
                    company: companyName(target.company),
                  }),
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </div>
          <Button
            type="button"
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('OUTSIDER_ERP.CANCEL')"
            @click="close"
          />
        </header>

        <div
          v-if="phase === 'loading'"
          class="flex items-center justify-center p-10"
        >
          <Spinner class="text-n-slate-10" />
        </div>

        <!-- convertida (agora ou antes, pelo chat) -->
        <template v-else-if="phase === 'done' && draft">
          <div class="flex-1 min-h-0 px-5 py-4 overflow-y-auto">
            <ErpOrderResult :draft="draft" />
            <p
              v-if="confirmCancel"
              class="p-3 mt-4 mb-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
            >
              {{ t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.CANCEL_CONFIRM_HINT') }}
            </p>
          </div>
          <footer
            class="flex flex-wrap items-center justify-end gap-2 px-5 py-3 border-t border-n-weak"
          >
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

        <template v-else>
          <div
            class="flex flex-col flex-1 min-h-0 gap-4 px-5 py-4 overflow-y-auto"
          >
            <p
              v-if="draftError && phase !== 'submitting'"
              class="flex items-start gap-2 p-3 mb-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
              data-erp-order-error
            >
              <Icon
                icon="i-lucide-circle-alert"
                class="mt-0.5 size-4 shrink-0"
              />
              <span>
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.DRAWER.NOT_RECORDED') }}
                {{ draftError }}
              </span>
            </p>

            <!-- conferência no ERP (só leitura) -->
            <section v-if="!halfDone" class="flex flex-col gap-1.5">
              <span
                class="text-[11px] font-medium tracking-wide uppercase text-n-slate-10"
              >
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.CHECKED') }}
              </span>
              <span
                v-if="previewLoading"
                class="flex items-center gap-2 text-sm text-n-slate-10"
              >
                <Spinner class="size-3.5" />
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.CHECKING') }}
              </span>
              <template v-else-if="preview">
                <div
                  v-for="check in checks"
                  :key="check.key"
                  class="flex items-start gap-2.5 text-sm"
                  :data-erp-convert-check="check.key"
                >
                  <span
                    class="flex items-center justify-center mt-px rounded-full shrink-0 size-5"
                    :class="
                      check.ok
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-ruby-3 text-n-ruby-11'
                    "
                  >
                    <Icon
                      :icon="check.ok ? 'i-lucide-check' : 'i-lucide-x'"
                      class="size-3"
                    />
                  </span>
                  <span
                    :class="check.ok ? 'text-n-slate-12' : 'text-n-ruby-11'"
                  >
                    {{ checkText(t, check) }}
                  </span>
                </div>
                <p
                  v-if="!checks.length && !preview.ok"
                  class="mb-0 text-sm text-n-ruby-11"
                >
                  {{ orderReasonText(t, preview.error) }}
                </p>
                <span
                  v-if="quote.itens"
                  class="text-xs text-n-slate-10"
                  data-erp-convert-quote
                >
                  {{
                    t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.QUOTE_LINE', {
                      count: quote.itens,
                      total: formatMoney(quote.total),
                    })
                  }}
                </span>
              </template>
            </section>

            <ErpOrderFields
              v-if="customerCode"
              v-model="fields"
              :company="target.company"
              :customer="customerCode"
              :options="options"
              kind="conversion"
              compact
              :read-only="
                halfDone ||
                phase === 'submitting' ||
                (preview && !preview.ok && !draft)
              "
              :missing="missing"
              :machine-note="t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.NO_MACHINE')"
            />

            <section
              class="flex flex-col gap-2 p-4 text-sm rounded-xl bg-n-alpha-1"
            >
              <span
                class="text-[11px] font-medium tracking-wide uppercase text-n-slate-10"
              >
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.WHAT_HAPPENS') }}
              </span>
              <div
                v-for="(step, index) in ['STEP_1', 'STEP_2', 'STEP_3']"
                :key="step"
                class="flex items-start gap-2.5 text-n-slate-12"
              >
                <span
                  class="flex items-center justify-center text-xs border rounded-full shrink-0 size-5 border-n-strong text-n-slate-11"
                >
                  {{ index + 1 }}
                </span>
                {{
                  t(`OUTSIDER_ERP.ORDER_DRAFT.CONVERT.${step}`, {
                    number: target.number,
                  })
                }}
              </div>
            </section>

            <div class="flex flex-wrap gap-x-6 gap-y-2 text-sm text-n-slate-12">
              <label
                class="flex items-center gap-2"
                :class="{ 'opacity-70': halfDone }"
              >
                <input
                  :checked="fields.agendar === true"
                  type="checkbox"
                  :disabled="halfDone || phase === 'submitting'"
                  @change="
                    fields = { ...fields, agendar: $event.target.checked }
                  "
                />
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.SCHEDULE') }}
              </label>
              <label
                class="flex items-center gap-2"
                :class="{ 'opacity-70': halfDone }"
              >
                <input
                  :checked="fields.enviar_app === true"
                  type="checkbox"
                  :disabled="halfDone || phase === 'submitting'"
                  @change="
                    fields = { ...fields, enviar_app: $event.target.checked }
                  "
                />
                {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.APP') }}
              </label>
            </div>
            <p v-if="erpUser" class="mb-0 text-xs text-n-slate-11">
              {{
                t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.WILL_RECORD_AS', {
                  name: erpUser.nome || `#${erpUser.codigo}`,
                })
              }}
            </p>
          </div>

          <footer
            class="flex flex-wrap items-center gap-2 px-5 py-3 border-t border-n-weak"
          >
            <span
              class="flex-1 min-w-[12rem] text-xs"
              :class="
                missing && missing !== 'loading' && phase !== 'submitting'
                  ? 'text-n-amber-11'
                  : 'text-n-slate-10'
              "
              data-erp-convert-footer
            >
              {{ footerText }}
            </span>
            <Button
              size="sm"
              variant="faded"
              color="slate"
              :label="t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.BACK')"
              @click="close"
            />
            <Button
              size="sm"
              icon="i-lucide-arrow-right-left"
              :label="
                halfDone || draft?.stuck
                  ? t('OUTSIDER_ERP.ORDER_DRAFT.ACTIONS.SUBMIT_AGAIN')
                  : t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.SUBMIT')
              "
              :is-loading="busy === 'convert' || phase === 'submitting'"
              :disabled="
                !!missing ||
                phase === 'submitting' ||
                (draft && !draft.can_submit)
              "
              data-erp-convert-submit
              @click="convert"
            />
          </footer>
        </template>
      </section>
    </div>
  </Teleport>
</template>
