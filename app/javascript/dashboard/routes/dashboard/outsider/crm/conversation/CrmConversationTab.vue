<script setup>
// OUTSIDER: aba "CRM" da conversa. Mostra um negócio do contato por vez: de início o aberto ligado a
// esta conversa (sem ele, o aberto do próprio usuário; sem ele, o aberto mais recente). Com mais de
// um negócio aberto, uma faixa no topo troca entre eles; clicar num negócio da lista "Outros
// negócios" ou do histórico também troca. Para o negócio mostrado: barra de etapas, tarefas, linha do
// tempo, auditoria e histórico multiempresa. "Encaminhar" leva o negócio para outra unidade do grupo.
// Usa o contato do Chatwoot: nada de cadastro duplicado. Grupos do WhatsApp não têm negócio.
// Entrega 20: sem o quadro de probabilidade (fica no negócio, para quem usa); a etapa já diz onde está.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OpportunityDialog from '../components/OpportunityDialog.vue';
import LostReasonDialog from '../components/LostReasonDialog.vue';
import ForwardDialog from '../components/ForwardDialog.vue';
import JourneyHistory from '../components/JourneyHistory.vue';
import OpportunityActivity from '../activity/OpportunityActivity.vue';
import ProposalMiniList from '../components/proposals/ProposalMiniList.vue';
import StageProgress from './StageProgress.vue';
import {
  crmState,
  findPipeline,
  isReceived,
  loadContactSummary,
  markReceived,
  refreshContact,
  summaryKey,
  unitName,
} from '../crmStore';
import {
  STATUS_COLORS,
  daysSince,
  daysUntil,
  errorMessage,
  formatDate,
  formatMoney,
  isHandedOff,
  lostMessage,
} from '../helpers';

const props = defineProps({
  chat: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUserId = useMapGetter('getCurrentUserID');
const { accountScopedRoute } = useAccount();
const router = useRouter();

const dialogRef = ref(null);
const lostDialogRef = ref(null);
const forwardDialogRef = ref(null);
const scrollRef = ref(null);
const isLoading = ref(false);
const isSaving = ref(false);
// negócio escolhido na faixa ou na lista; vazio = o principal que a API indicou
const selectedId = ref(null);

const contact = computed(() => props.chat.meta?.sender || {});
const summary = computed(
  () => crmState.summaries[summaryKey(contact.value.id, props.chat.id)]
);
const opportunities = computed(() => summary.value?.opportunities || []);
const primary = computed(
  () =>
    opportunities.value.find(item => item.id === selectedId.value) ||
    opportunities.value.find(item => item.id === summary.value?.primary_id)
);
const others = computed(() =>
  opportunities.value.filter(item => item.id !== primary.value?.id)
);
// faixa de troca: os abertos, o principal da API primeiro
const openDeals = computed(() => {
  const open = opportunities.value.filter(item => item.status === 'open');
  const main = open.filter(item => item.id === summary.value?.primary_id);
  return [
    ...main,
    ...open.filter(item => item.id !== summary.value?.primary_id),
  ];
});
const showSwitcher = computed(
  () =>
    openDeals.value.length > 1 ||
    (openDeals.value.length === 1 && primary.value?.status !== 'open')
);
const primaryPipeline = computed(
  () => primary.value && findPipeline(primary.value.pipeline_id)
);
const canCreate = computed(() => !!summary.value?.creatable_unit_ids?.length);
// sem negócio aberto: o último desta conversa que saiu para outra unidade explica para onde foi
const lastForwarded = computed(() =>
  opportunities.value.find(
    item => isHandedOff(item) && item.conversation_display_id === props.chat.id
  )
);

const closeInfo = computed(() => {
  const days = daysUntil(primary.value?.expected_close_on);
  if (days === null) return t('OUTSIDER_CRM.CONVERSATION.NO_CLOSE_DATE');
  if (days > 0) return t('OUTSIDER_CRM.CONVERSATION.DAYS_LEFT', { days });
  if (days === 0) return t('OUTSIDER_CRM.CONVERSATION.DUE_TODAY');
  return t('OUTSIDER_CRM.CONVERSATION.DAYS_LATE', { days: -days });
});

const daysInStage = computed(() => daysSince(primary.value?.stage_changed_at));

const load = async () => {
  isLoading.value = !summary.value;
  try {
    await loadContactSummary(contact.value.id, props.chat.id);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const afterChange = () => refreshContact(contact.value.id);

const openNew = () =>
  dialogRef.value?.open(null, {
    contact: contact.value,
    conversation_display_id: props.chat.id,
    unit_ids: summary.value.creatable_unit_ids,
    business_unit_id: summary.value.creatable_unit_ids[0],
  });

const openEdit = opportunity => dialogRef.value?.open(opportunity);

// message pode ser uma função da resposta (o aviso de perdido diz para onde o negócio foi)
const update = async (opportunity, attributes, message) => {
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateOpportunity(opportunity.id, attributes);
    useAlert(typeof message === 'function' ? message(data) : message);
    await afterChange();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

const moveTo = stage =>
  update(
    primary.value,
    { stage_id: stage.id },
    t('OUTSIDER_CRM.CONVERSATION.MOVED', { stage: stage.name })
  );

const markWon = () =>
  update(
    primary.value,
    { status: 'won' },
    t('OUTSIDER_CRM.BOARD.WON_DONE', { title: primary.value.title })
  );

const select = opportunity => {
  selectedId.value = opportunity.id;
  scrollRef.value?.scrollTo({ top: 0, behavior: 'smooth' });
};

const openFromHistory = item => {
  const opportunity = opportunities.value.find(entry => entry.id === item.id);
  if (opportunity) select(opportunity);
};

// negócio de outra conversa (ex.: o que bloqueia o encaminhamento): abre no painel do CRM
const openElsewhere = item => {
  if (opportunities.value.some(entry => entry.id === item.id)) {
    openFromHistory(item);
    return;
  }
  router.push(
    accountScopedRoute(
      'outsider_crm',
      { tab: 'opportunities' },
      { negocio: item.id }
    )
  );
};

const markLost = (opportunity, reasonId) =>
  update(opportunity, { status: 'lost', lost_reason_id: reasonId }, saved =>
    lostMessage(t, opportunity.title, saved)
  );

watch(
  () => [contact.value.id, props.chat.id],
  () => {
    selectedId.value = null;
    load();
  }
);

// abrir aqui um negócio recebido por encaminhamento tira o aviso dele
watch(
  () => primary.value?.id,
  id => {
    if (id) markReceived([id], true);
  },
  { immediate: true }
);

onMounted(async () => {
  await load();
  if (!agents.value.length) store.dispatch('agents/get');
  // pedido do painel do contato: "Criar negócio" abre a aba já com o formulário
  if (crmState.pendingCreate === contact.value.id && canCreate.value) {
    openNew();
  }
  crmState.pendingCreate = null;
});
</script>

<template>
  <div
    ref="scrollRef"
    class="h-full min-h-0 px-4 py-4 overflow-y-auto bg-n-surface-1"
  >
    <div class="flex flex-col w-full max-w-4xl gap-4 mx-auto">
      <div class="flex flex-wrap items-center gap-2">
        <div class="flex flex-col flex-1 min-w-0">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.CONVERSATION.TITLE') }}
          </span>
          <span v-if="summary" class="text-xs text-n-slate-11">
            {{
              t('OUTSIDER_CRM.CONVERSATION.SUMMARY', {
                open: summary.open_count,
                value: formatMoney(summary.open_value_cents),
                won: summary.won_count,
              })
            }}
          </span>
        </div>
        <Spinner v-if="isSaving" :size="16" class="text-n-slate-10" />
        <router-link
          :to="accountScopedRoute('outsider_crm', { tab: 'opportunities' })"
          class="text-sm text-n-blue-11 hover:underline"
        >
          {{ t('OUTSIDER_CRM.CONVERSATION.OPEN_CRM') }}
        </router-link>
        <Button
          v-if="canCreate"
          type="button"
          icon="i-lucide-plus"
          size="sm"
          :label="t('OUTSIDER_CRM.OPPORTUNITY.NEW')"
          @click="openNew"
        />
      </div>

      <div v-if="isLoading" class="flex justify-center p-8 text-n-slate-10">
        <Spinner />
      </div>

      <template v-else-if="summary">
        <p
          v-if="summary.group"
          class="flex items-center gap-2 p-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
        >
          <Icon icon="i-lucide-users" class="size-4 shrink-0" />
          {{ t('OUTSIDER_CRM.CONVERSATION.GROUP') }}
        </p>

        <div
          v-else-if="!primary"
          class="flex flex-col items-center gap-3 p-8 text-center rounded-xl bg-n-alpha-1"
        >
          <Icon icon="i-lucide-handshake" class="size-8 text-n-slate-9" />
          <p v-if="lastForwarded" class="max-w-md mb-0 text-sm text-n-slate-11">
            {{
              t('OUTSIDER_CRM.FORWARD.CONVERSATION_FORWARDED', {
                code: lastForwarded.code,
                unit: lastForwarded.forwarded_to?.business_unit_name || '—',
              })
            }}
          </p>
          <p class="max-w-md mb-0 text-sm text-n-slate-11">
            {{
              canCreate
                ? t('OUTSIDER_CRM.CONVERSATION.EMPTY')
                : t('OUTSIDER_CRM.CONVERSATION.EMPTY_NO_UNIT')
            }}
          </p>
          <Button
            v-if="canCreate"
            type="button"
            icon="i-lucide-plus"
            size="sm"
            :label="t('OUTSIDER_CRM.CONVERSATION.CREATE')"
            @click="openNew"
          />
        </div>

        <div v-if="showSwitcher" class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('OUTSIDER_CRM.CONVERSATION.SWITCH', openDeals.length) }}
          </span>
          <div class="flex gap-2 pb-1 overflow-x-auto">
            <button
              v-for="deal in openDeals"
              :key="deal.id"
              type="button"
              class="flex flex-col gap-0.5 px-3 py-2 text-start rounded-xl shrink-0 w-56 outline outline-1 -outline-offset-1 transition-colors"
              :class="
                deal.id === primary?.id
                  ? 'bg-n-solid-2 outline-n-brand'
                  : 'bg-n-alpha-1 outline-transparent hover:outline-n-weak'
              "
              :aria-pressed="deal.id === primary?.id"
              @click="select(deal)"
            >
              <span
                class="flex items-center gap-1 text-xs truncate text-n-slate-11"
              >
                <span
                  v-if="isReceived(deal.id)"
                  class="px-1 text-[11px] font-semibold rounded bg-n-ruby-9 text-white"
                >
                  {{ t('OUTSIDER_CRM.NOTICE.NEW') }}
                </span>
                {{ deal.code }} · {{ unitName(deal.business_unit_id) }}
              </span>
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ deal.title }}
              </span>
              <span class="flex items-center gap-1 text-xs text-n-slate-11">
                <span class="font-medium text-n-teal-11">
                  {{ formatMoney(deal.value_cents) }}
                </span>
                ·
                <span class="truncate">
                  {{
                    deal.owner?.id === currentUserId
                      ? t('OUTSIDER_CRM.CONVERSATION.YOURS')
                      : deal.owner?.name ||
                        t('OUTSIDER_CRM.CONVERSATION.NO_OWNER')
                  }}
                </span>
              </span>
            </button>
          </div>
        </div>

        <section
          v-if="primary"
          class="flex flex-col gap-4 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <p
            v-if="primary.forwarded_from"
            class="flex items-center gap-2 px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
          >
            <Icon icon="i-lucide-inbox" class="size-4 shrink-0" />
            {{
              t('OUTSIDER_CRM.FORWARD.RECEIVED_FROM', {
                unit: primary.forwarded_from.business_unit_name,
                code: primary.forwarded_from.code,
              })
            }}
          </p>
          <div class="flex flex-wrap items-start gap-3">
            <div class="flex flex-col flex-1 min-w-0 gap-1">
              <div class="flex flex-wrap items-center gap-1.5 text-xs">
                <span
                  class="px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11"
                >
                  {{ primary.code }}
                </span>
                <span
                  class="px-1.5 py-0.5 rounded-md"
                  :class="STATUS_COLORS[primary.status]"
                >
                  {{ t(`OUTSIDER_CRM.STATUS.${primary.status.toUpperCase()}`) }}
                </span>
                <span
                  v-if="primary.conversation_display_id === chat.id"
                  class="px-1.5 py-0.5 rounded-md bg-n-blue-3 text-n-blue-11"
                >
                  {{ t('OUTSIDER_CRM.CONVERSATION.FROM_THIS_CONVERSATION') }}
                </span>
                <span class="text-n-slate-11">
                  {{ unitName(primary.business_unit_id) }}
                  <template v-if="primaryPipeline">
                    · {{ primaryPipeline.name }}
                  </template>
                </span>
              </div>
              <h3 class="mb-0 text-base font-medium text-n-slate-12">
                {{ primary.title }}
              </h3>
              <span class="text-xs text-n-slate-11">
                {{
                  t('OUTSIDER_CRM.CONVERSATION.CREATED_AT', {
                    date: formatDate(primary.created_at.slice(0, 10)),
                  })
                }}
              </span>
            </div>
            <div class="flex flex-col items-end gap-2">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.CONVERSATION.EXPECTED_VALUE') }}
              </span>
              <span class="text-xl font-semibold text-n-teal-11">
                {{ formatMoney(primary.value_cents) }}
              </span>
            </div>
          </div>

          <div class="flex flex-wrap gap-2">
            <Button
              type="button"
              size="sm"
              variant="faded"
              color="slate"
              :icon="primary.can_edit ? 'i-lucide-pencil' : 'i-lucide-eye'"
              :label="
                primary.can_edit
                  ? t('OUTSIDER_CRM.CONVERSATION.EDIT')
                  : t('OUTSIDER_CRM.CONVERSATION.VIEW')
              "
              @click="openEdit(primary)"
            />
            <template v-if="primary.can_edit && primary.status === 'open'">
              <Button
                type="button"
                size="sm"
                variant="faded"
                color="teal"
                icon="i-lucide-trophy"
                :label="t('OUTSIDER_CRM.CONVERSATION.MARK_WON')"
                :disabled="isSaving"
                @click="markWon"
              />
              <Button
                type="button"
                size="sm"
                variant="faded"
                color="ruby"
                icon="i-lucide-circle-x"
                :label="t('OUTSIDER_CRM.BOARD.MARK_LOST')"
                :disabled="isSaving"
                @click="lostDialogRef?.open(primary)"
              />
            </template>
            <Button
              v-if="primary.can_forward"
              type="button"
              size="sm"
              variant="faded"
              color="amber"
              icon="i-lucide-forward"
              :label="t('OUTSIDER_CRM.FORWARD.BUTTON')"
              :disabled="isSaving"
              @click="forwardDialogRef?.open(primary)"
            />
          </div>

          <div
            v-if="primaryPipeline"
            class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1"
          >
            <div
              class="flex flex-wrap items-center justify-between gap-2 text-xs"
            >
              <span class="font-medium text-n-slate-11">
                {{ t('OUTSIDER_CRM.CONVERSATION.CURRENT_STAGE') }}
              </span>
              <span class="flex items-center gap-2 text-n-slate-11">
                <span
                  v-if="primary.sla_exceeded"
                  class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-n-amber-3 text-n-amber-11"
                >
                  <Icon icon="i-lucide-clock-alert" class="size-3" />
                  {{ t('OUTSIDER_CRM.BOARD.SLA') }}
                </span>
                <template v-if="daysInStage !== null">
                  {{
                    t('OUTSIDER_CRM.CONVERSATION.DAYS_IN_STAGE', {
                      days: daysInStage,
                    })
                  }}
                </template>
              </span>
            </div>
            <StageProgress
              :pipeline="primaryPipeline"
              :stage-id="primary.stage_id"
              :status="primary.status"
              :can-move="primary.can_edit && !isSaving"
              @move="moveTo"
            />
          </div>

          <div class="grid grid-cols-2 gap-3 lg:grid-cols-3">
            <div class="flex flex-col gap-0.5 p-3 rounded-lg bg-n-alpha-1">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.OPPORTUNITY.CLOSE_DATE') }}
              </span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ formatDate(primary.expected_close_on) || '—' }}
              </span>
              <span
                class="text-xs"
                :class="primary.overdue ? 'text-n-ruby-11' : 'text-n-slate-10'"
              >
                {{ closeInfo }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5 p-3 rounded-lg bg-n-alpha-1">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.OPPORTUNITY.OWNER') }}
              </span>
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ primary.owner?.name || '—' }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{ unitName(primary.business_unit_id) }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5 p-3 rounded-lg bg-n-alpha-1">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.CONVERSATION.TOTAL_OPEN') }}
              </span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ formatMoney(summary.open_value_cents) }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{
                  t('OUTSIDER_CRM.CONVERSATION.OPEN_DEALS', {
                    count: summary.open_count,
                  })
                }}
              </span>
            </div>
          </div>
        </section>

        <section
          v-if="primary"
          class="p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <OpportunityActivity
            :opportunity="primary"
            :conversation-display-id="chat.id"
            :show-proposals="false"
            @changed="afterChange"
          />
        </section>

        <section
          v-if="!summary.group"
          class="flex flex-col gap-2 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSALS.MINI.CONTACT_TITLE') }}
          </span>
          <ProposalMiniList
            :contact-id="contact.id"
            :new-opportunity-id="primary?.status === 'open' ? primary.id : null"
          />
        </section>

        <JourneyHistory
          v-if="!summary.group"
          :contact-id="contact.id"
          :opportunity-id="primary?.id || null"
          boxed
          @open="openFromHistory"
        />

        <section v-if="others.length" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.CONVERSATION.OTHERS') }}
          </span>
          <div
            class="overflow-hidden rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
          >
            <button
              v-for="opportunity in others"
              :key="opportunity.id"
              type="button"
              class="flex items-center w-full gap-3 px-4 py-3 text-sm border-b text-start border-n-weak last:border-0 hover:bg-n-alpha-1"
              @click="select(opportunity)"
            >
              <div class="flex flex-col flex-1 min-w-0">
                <span class="font-medium truncate text-n-slate-12">
                  {{ opportunity.title }}
                </span>
                <span class="text-xs truncate text-n-slate-11">
                  {{ opportunity.code }} ·
                  {{ unitName(opportunity.business_unit_id) }}
                  <template v-if="opportunity.forwarded_to">
                    ·
                    {{
                      t('OUTSIDER_CRM.FORWARD.TO_UNIT', {
                        unit: opportunity.forwarded_to.business_unit_name,
                      })
                    }}
                  </template>
                  <template v-if="opportunity.closed_at">
                    · {{ formatDate(opportunity.closed_at.slice(0, 10)) }}
                  </template>
                </span>
              </div>
              <span
                class="px-2 py-0.5 text-xs rounded-md shrink-0"
                :class="STATUS_COLORS[opportunity.status]"
              >
                {{
                  t(`OUTSIDER_CRM.STATUS.${opportunity.status.toUpperCase()}`)
                }}
              </span>
              <span
                class="w-28 font-medium text-right shrink-0 text-n-slate-12"
              >
                {{ formatMoney(opportunity.value_cents) }}
              </span>
            </button>
          </div>
        </section>
      </template>
    </div>

    <OpportunityDialog
      ref="dialogRef"
      :access="crmState.access"
      :pipelines="crmState.pipelines"
      :agents="agents"
      @saved="afterChange"
    />
    <LostReasonDialog
      ref="lostDialogRef"
      :lost-reasons="crmState.lostReasons"
      @confirm="markLost"
    />
    <ForwardDialog
      ref="forwardDialogRef"
      :unit-name="primary ? unitName(primary.business_unit_id) : ''"
      @forwarded="afterChange"
      @open="openElsewhere"
    />
  </div>
</template>
