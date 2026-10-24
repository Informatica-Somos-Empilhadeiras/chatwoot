<script setup>
// OUTSIDER: negócios abertos de um contato com o pipeline de cada um (Entrega 20). Usado no bloco CRM do
// painel do contato (conversa) e na aba CRM da página do contato. A barra mostra em que etapa o negócio
// está; quem pode editar clica numa etapa para mover. O negócio da conversa vem primeiro.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import StageProgress from './StageProgress.vue';
import {
  crmState,
  findPipeline,
  refreshContact,
  summaryKey,
  unitName,
} from '../crmStore';
import { errorMessage, formatMoney } from '../helpers';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const movingId = ref(null);

const summary = computed(
  () => crmState.summaries[summaryKey(props.contactId, props.conversationId)]
);

const openDeals = computed(() =>
  (summary.value?.opportunities || [])
    .filter(item => item.status === 'open')
    .sort(
      (a, b) =>
        (b.id === summary.value.primary_id) -
        (a.id === summary.value.primary_id)
    )
);

const subtitle = deal =>
  [unitName(deal.business_unit_id), findPipeline(deal.pipeline_id)?.name]
    .filter(Boolean)
    .join(' · ');

const move = async (deal, stage) => {
  movingId.value = deal.id;
  try {
    await CrmAPI.updateOpportunity(deal.id, { stage_id: stage.id });
    useAlert(t('OUTSIDER_CRM.CONVERSATION.MOVED', { stage: stage.name }));
    await refreshContact(props.contactId);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    movingId.value = null;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="deal in openDeals"
      :key="deal.id"
      class="flex flex-col gap-2 p-2.5 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <button
        type="button"
        class="flex flex-col gap-0.5 text-start group"
        :title="deal.code"
        @click="emit('open', deal)"
      >
        <span class="flex items-center justify-between gap-2">
          <span
            class="font-medium truncate text-n-slate-12 group-hover:underline"
          >
            {{ deal.title }}
          </span>
          <span class="font-medium shrink-0 text-n-slate-12">
            {{ formatMoney(deal.value_cents) }}
          </span>
        </span>
        <span v-if="subtitle(deal)" class="text-xs truncate text-n-slate-11">
          {{ subtitle(deal) }}
        </span>
      </button>
      <StageProgress
        :pipeline="findPipeline(deal.pipeline_id)"
        :stage-id="deal.stage_id"
        :status="deal.status"
        :can-move="deal.can_edit && movingId !== deal.id"
        compact
        @move="stage => move(deal, stage)"
      />
    </div>
    <p v-if="!openDeals.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_CRM.CONVERSATION.PANEL_EMPTY') }}
    </p>
  </div>
</template>
