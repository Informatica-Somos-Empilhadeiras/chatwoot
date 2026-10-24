<script setup>
// OUTSIDER: bloco "CRM" no painel do contato dentro da conversa. Resume os negócios do contato,
// mostra as unidades do grupo com quem ele já negociou (histórico multiempresa) e leva para a aba
// CRM da conversa (o detalhe e as ações ficam lá). Entrega 20: cada negócio aberto mostra o pipeline
// (ContactDeals); quem pode editar muda a etapa ali mesmo.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import JourneyHistory from '../components/JourneyHistory.vue';
import ContactDeals from './ContactDeals.vue';
import {
  OPEN_CRM_TAB_EVENT,
  crmState,
  loadContactSummary,
  summaryKey,
} from '../crmStore';
import { formatMoney } from '../helpers';

const props = defineProps({
  contactId: { type: Number, default: null },
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const { isContactSidebarItemOpen, toggleSidebarUIState } = useUISettings();
const { accountScopedRoute } = useAccount();

const summary = computed(
  () =>
    crmState.summaries[
      summaryKey(props.contactId, Number(props.conversationId))
    ]
);
const openTab = () => emitter.emit(OPEN_CRM_TAB_EVENT);

const createDeal = () => {
  crmState.pendingCreate = props.contactId;
  openTab();
};

// access.enabled: o CRM religado com a conversa aberta busca o resumo na hora
watch(
  () => [props.contactId, props.conversationId, crmState.access.enabled],
  () =>
    loadContactSummary(props.contactId, Number(props.conversationId)).catch(
      () => {}
    ),
  { immediate: true }
);
</script>

<template>
  <AccordionItem
    v-if="crmState.access.enabled && summary && !summary.group"
    :title="t('OUTSIDER_CRM.CONVERSATION.PANEL_TITLE')"
    :is-open="isContactSidebarItemOpen('is_outsider_crm_open')"
    compact
    @toggle="value => toggleSidebarUIState('is_outsider_crm_open', value)"
  >
    <div class="flex flex-col gap-3 px-2 pb-1 text-sm">
      <div class="grid grid-cols-2 gap-2">
        <div class="flex flex-col p-2 rounded-lg bg-n-alpha-1">
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.METRICS.OPEN') }}
          </span>
          <span class="font-semibold text-n-slate-12">
            {{ formatMoney(summary.open_value_cents) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              t('OUTSIDER_CRM.CONVERSATION.DEALS', {
                count: summary.open_count,
              })
            }}
          </span>
        </div>
        <div class="flex flex-col p-2 rounded-lg bg-n-alpha-1">
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.CONVERSATION.WON') }}
          </span>
          <span class="font-semibold text-n-slate-12">
            {{ formatMoney(summary.won_value_cents) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              t('OUTSIDER_CRM.CONVERSATION.DEALS', { count: summary.won_count })
            }}
          </span>
        </div>
      </div>

      <ContactDeals
        :contact-id="contactId"
        :conversation-id="Number(conversationId)"
        @open="openTab"
      />

      <JourneyHistory :contact-id="contactId" compact />

      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-if="summary.creatable_unit_ids.length"
          type="button"
          size="xs"
          icon="i-lucide-plus"
          :label="t('OUTSIDER_CRM.CONVERSATION.CREATE')"
          @click="createDeal"
        />
        <Button
          type="button"
          size="xs"
          variant="faded"
          color="slate"
          :label="t('OUTSIDER_CRM.CONVERSATION.OPEN_TAB')"
          @click="openTab"
        />
        <router-link
          :to="accountScopedRoute('outsider_crm', { tab: 'opportunities' })"
          class="text-xs text-n-blue-11 hover:underline"
        >
          {{ t('OUTSIDER_CRM.CONVERSATION.OPEN_CRM') }}
        </router-link>
      </div>
    </div>
  </AccordionItem>
</template>
