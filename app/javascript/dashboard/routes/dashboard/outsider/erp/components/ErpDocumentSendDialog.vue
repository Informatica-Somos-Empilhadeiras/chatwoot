<script setup>
// OUTSIDER: envio de um PDF do ERP ao cliente, na mesma tela do orçamento (ErpBudgetSend, com o documento como fonte):
// a prévia e o envio por WhatsApp ou e-mail. kind: orders (o relatório da OS com as fotos do checklist), invoices (NF-e)
// ou service_invoices (NFS-e), as duas do Nextcloud. Abre do detalhe da OS/nota (seção ERP) e do cartão da OS. O contato
// vem o escolhido, senão o da conversa, senão o vinculado ao cliente do ERP.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import ErpBudgetSend from '../budgets/ErpBudgetSend.vue';

const { t } = useI18n();
const isOpen = ref(false);
const target = ref({});

// options: { kind, company, code, contactId, conversationId, clientCode }; kind padrão: orders
const open = options => {
  target.value = { kind: 'orders', ...options };
  isOpen.value = true;
};

const close = () => {
  isOpen.value = false;
};

const isOrder = computed(() => target.value.kind === 'orders');

// textos da tela de cada tipo (os da OS em ORDER.SEND, os das notas em RECORDS.INVOICE.SEND)
const texts = computed(() => {
  const { kind, code } = target.value;
  if (kind === 'orders')
    return {
      title: t('OUTSIDER_ERP.ORDER.SEND.TITLE', { code }),
      pdfTitle: t('OUTSIDER_ERP.ORDER.SEND.PDF_TITLE'),
      hint: t('OUTSIDER_ERP.ORDER.SEND.HINT'),
      emailDone: t('OUTSIDER_ERP.ORDER.SEND.EMAIL_DONE'),
      whatsappDone: t('OUTSIDER_ERP.ORDER.SEND.WHATSAPP_DONE'),
    };
  return {
    title: t('OUTSIDER_ERP.RECORDS.INVOICE.SEND.TITLE'),
    pdfTitle: t('OUTSIDER_ERP.RECORDS.INVOICE.SEND.PDF_TITLE'),
    hint: t('OUTSIDER_ERP.RECORDS.INVOICE.SEND.HINT'),
    emailDone: t('OUTSIDER_ERP.RECORDS.INVOICE.SEND.EMAIL_DONE'),
    whatsappDone: t('OUTSIDER_ERP.RECORDS.INVOICE.SEND.WHATSAPP_DONE'),
  };
});

const orderSource = (base, { company, code, contactId, clientCode }) => ({
  pdf: () => ErpAPI.serviceOrderReport(company, code),
  delivery: () =>
    ErpAPI.serviceOrderDelivery({
      ...base,
      company,
      code,
      contact_id: contactId || undefined,
      client_code: clientCode || undefined,
    }),
  contacts: q => ErpAPI.serviceOrderContacts(q),
  deliver: payload =>
    ErpAPI.deliverServiceOrder({ ...base, company, code, ...payload }),
});

const invoiceSource = (
  base,
  { kind, company, code, contactId, clientCode }
) => ({
  pdf: () => ErpAPI.invoiceDocument(kind, company, code),
  delivery: () =>
    ErpAPI.invoiceDelivery(kind, company, code, {
      ...base,
      contact_id: contactId || undefined,
      client_code: clientCode || undefined,
    }),
  contacts: q => ErpAPI.invoiceContacts(q),
  deliver: payload =>
    ErpAPI.deliverInvoice(kind, company, code, { ...base, ...payload }),
});

const source = computed(() => {
  const base = {
    conversation_id: target.value.conversationId || undefined,
  };
  const build = isOrder.value ? orderSource : invoiceSource;
  const { title, ...labels } = texts.value;
  return { ...build(base, target.value), labels };
});

defineExpose({ open, isOpen });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[10000] flex flex-col bg-n-alpha-black1 backdrop-blur-[2px]"
      @keydown.esc="close"
    >
      <div
        class="flex flex-col w-full h-full max-w-6xl mx-auto overflow-hidden shadow-xl sm:my-6 sm:h-[calc(100%-3rem)] sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header
          class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
        >
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ texts.title }}
          </span>
          <Button
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('OUTSIDER_ERP.CANCEL')"
            @click="close"
          />
        </header>
        <div class="flex flex-col flex-1 min-h-0 p-4 overflow-y-auto">
          <ErpBudgetSend
            :key="`${target.kind}:${target.company}:${target.code}`"
            class="flex-1 min-h-0"
            :source="source"
            @sent="close"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
