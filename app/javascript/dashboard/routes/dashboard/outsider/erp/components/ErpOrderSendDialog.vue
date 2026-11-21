<script setup>
// OUTSIDER: envio do relatório da OS (o PDF com as fotos do checklist) ao cliente: a prévia do PDF e o envio por WhatsApp
// ou e-mail, na mesma tela do orçamento (ErpBudgetSend, com a OS como fonte). Abre do detalhe da OS (seção ERP) e do
// cartão da OS (quadro e conversa). O contato vem o escolhido, senão o da conversa, senão o vinculado ao cliente da OS.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import ErpBudgetSend from '../budgets/ErpBudgetSend.vue';

const { t } = useI18n();
const isOpen = ref(false);
const target = ref({});

// options: { company, code, contactId, conversationId, clientCode }
const open = options => {
  target.value = options;
  isOpen.value = true;
};

const close = () => {
  isOpen.value = false;
};

const source = computed(() => {
  const { company, code, contactId, conversationId, clientCode } = target.value;
  const base = { company, code, conversation_id: conversationId || undefined };
  return {
    pdf: () => ErpAPI.serviceOrderReport(company, code),
    delivery: () =>
      ErpAPI.serviceOrderDelivery({
        ...base,
        contact_id: contactId || undefined,
        client_code: clientCode || undefined,
      }),
    contacts: q => ErpAPI.serviceOrderContacts(q),
    deliver: payload => ErpAPI.deliverServiceOrder({ ...base, ...payload }),
    labels: {
      pdfTitle: t('OUTSIDER_ERP.ORDER.SEND.PDF_TITLE'),
      hint: t('OUTSIDER_ERP.ORDER.SEND.HINT'),
      emailDone: t('OUTSIDER_ERP.ORDER.SEND.EMAIL_DONE'),
      whatsappDone: t('OUTSIDER_ERP.ORDER.SEND.WHATSAPP_DONE'),
    },
  };
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
            {{ t('OUTSIDER_ERP.ORDER.SEND.TITLE', { code: target.code }) }}
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
            :key="`${target.company}:${target.code}`"
            class="flex-1 min-h-0"
            :source="source"
            @sent="close"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
