<script setup>
// OUTSIDER: propostas de um negócio (aba Propostas do negócio) ou de um contato (aba CRM da conversa).
// Só as que a pessoa pode ver. "Nova proposta" abre o editor no CRM já com o contato e o negócio;
// o ícone mostra o PDF ali mesmo.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ProposalPdfDialog from './ProposalPdfDialog.vue';
import { errorMessage, formatDate, formatMoney } from '../../helpers';
import { PROPOSAL_STATUS_COLORS, proposalRoute } from './proposalHelpers';

const props = defineProps({
  contactId: { type: Number, required: true },
  opportunityId: { type: Number, default: null },
  // negócio aberto do contato: a proposta nova já vem ligada a ele
  newOpportunityId: { type: Number, default: null },
  canCreate: { type: Boolean, default: true },
});

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const proposals = ref([]);
const count = ref(0);
const isLoading = ref(false);
const pdfRef = ref(null);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getProposals(
      props.opportunityId
        ? { opportunity_id: props.opportunityId }
        : { contact_id: props.contactId }
    );
    proposals.value = data.payload;
    count.value = data.meta.count;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const open = proposal =>
  router.push(proposalRoute(accountScopedRoute, { proposta: proposal.id }));

const openNew = (kind = 'sale') =>
  router.push(
    proposalRoute(accountScopedRoute, {
      proposta: 'nova',
      contato: props.contactId,
      negocio: props.opportunityId || props.newOpportunityId || undefined,
      tipo: kind,
    })
  );

watch(() => [props.contactId, props.opportunityId], load, {
  immediate: true,
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center gap-2">
      <span class="flex-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.MINI.COUNT', { count }) }}
      </span>
      <Spinner v-if="isLoading" :size="14" class="text-n-slate-10" />
      <template v-if="canCreate">
        <Button
          size="xs"
          variant="faded"
          color="slate"
          icon="i-lucide-plus"
          :label="t('OUTSIDER_CRM.PROPOSALS.MINI.NEW_SALE')"
          @click="openNew('sale')"
        />
        <Button
          size="xs"
          variant="faded"
          color="slate"
          icon="i-lucide-plus"
          :label="t('OUTSIDER_CRM.PROPOSALS.MINI.NEW_RENTAL')"
          @click="openNew('rental')"
        />
      </template>
    </div>
    <p
      v-if="!proposals.length && !isLoading"
      class="p-3 mb-0 text-sm text-center rounded-lg text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('OUTSIDER_CRM.PROPOSALS.MINI.EMPTY') }}
    </p>
    <div
      v-for="proposal in proposals"
      :key="proposal.id"
      class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer bg-n-alpha-1 hover:bg-n-alpha-2"
      @click="open(proposal)"
    >
      <div class="flex flex-col flex-1 min-w-0">
        <span class="text-sm truncate text-n-slate-12">
          <strong class="font-medium">{{ proposal.number }}</strong>
          · {{ proposal.title }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t(`OUTSIDER_CRM.PROPOSALS.KIND.${proposal.kind.toUpperCase()}`) }}
          · {{ formatDate(proposal.issued_on) }}
          <template v-if="proposal.owner">· {{ proposal.owner.name }}</template>
          <template v-if="!opportunityId && proposal.opportunity">
            · {{ proposal.opportunity.code }}
          </template>
        </span>
      </div>
      <span class="text-sm font-medium whitespace-nowrap text-n-slate-12">
        {{ formatMoney(proposal.total_cents) }}
      </span>
      <span
        class="px-2 py-0.5 text-xs rounded-md whitespace-nowrap"
        :class="PROPOSAL_STATUS_COLORS[proposal.display_status]"
      >
        {{
          t(
            `OUTSIDER_CRM.PROPOSALS.STATUS.${proposal.display_status.toUpperCase()}`
          )
        }}
      </span>
      <Button
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSALS.PDF.VIEW')"
        size="xs"
        variant="ghost"
        color="slate"
        icon="i-lucide-file-search"
        @click.stop="pdfRef?.open(proposal)"
      />
    </div>
    <ProposalPdfDialog ref="pdfRef" />
  </div>
</template>
