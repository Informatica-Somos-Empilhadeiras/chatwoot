<script setup>
// OUTSIDER: aba "CRM" da página do contato (Contatos > contato), Entrega 20. Mostra quanto o contato tem
// em aberto e já ganhou, os negócios abertos com o pipeline de cada um (dá para mudar a etapa ali) e o
// histórico com as unidades do grupo. "Novo negócio" abre o mesmo cadastro do CRM, já com o contato.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import OpportunityDialog from '../components/OpportunityDialog.vue';
import JourneyHistory from '../components/JourneyHistory.vue';
import ContactDeals from './ContactDeals.vue';
import {
  crmState,
  loadContactSummary,
  refreshContact,
  summaryKey,
} from '../crmStore';
import { formatMoney } from '../helpers';

const props = defineProps({
  contact: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const { accountScopedRoute } = useAccount();

const dialogRef = ref(null);
const isLoading = ref(true);

const summary = computed(
  () => crmState.summaries[summaryKey(props.contact.id, null)]
);

const load = async () => {
  isLoading.value = true;
  try {
    await loadContactSummary(props.contact.id, null);
  } catch {
    // sem o resumo, a aba mostra o aviso de vazio
  } finally {
    isLoading.value = false;
  }
};

const openDeal = deal =>
  router.push(
    accountScopedRoute(
      'outsider_crm',
      { tab: 'opportunities' },
      { negocio: deal.id }
    )
  );

const createDeal = () => {
  if (!agents.value.length) store.dispatch('agents/get');
  dialogRef.value?.open(null, {
    contact: props.contact,
    unit_ids: summary.value.creatable_unit_ids,
    business_unit_id: summary.value.creatable_unit_ids[0],
  });
};

watch(() => props.contact.id, load, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-4 px-6 pb-6 text-sm">
    <div v-if="isLoading" class="flex justify-center py-8">
      <Spinner class="text-n-slate-10" />
    </div>
    <template v-else-if="summary">
      <div class="grid grid-cols-2 gap-2">
        <div class="flex flex-col p-3 rounded-lg bg-n-alpha-1">
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
        <div class="flex flex-col p-3 rounded-lg bg-n-alpha-1">
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

      <div class="flex items-center justify-between gap-2">
        <span class="font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.CONVERSATION.CONTACT_DEALS') }}
        </span>
        <Button
          v-if="summary.creatable_unit_ids.length"
          type="button"
          size="xs"
          icon="i-lucide-plus"
          :label="t('OUTSIDER_CRM.OPPORTUNITY.NEW')"
          @click="createDeal"
        />
      </div>
      <ContactDeals :contact-id="contact.id" @open="openDeal" />

      <JourneyHistory :contact-id="contact.id" compact />
    </template>
    <p v-else class="mb-0 text-n-slate-11">
      {{ t('OUTSIDER_CRM.CONVERSATION.PANEL_EMPTY') }}
    </p>

    <OpportunityDialog
      ref="dialogRef"
      :access="crmState.access"
      :pipelines="crmState.pipelines"
      :agents="agents"
      @saved="refreshContact(contact.id)"
    />
  </div>
</template>
