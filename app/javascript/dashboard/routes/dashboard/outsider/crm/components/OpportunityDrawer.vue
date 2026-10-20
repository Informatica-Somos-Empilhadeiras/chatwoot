<script setup>
// OUTSIDER: painel lateral de um negócio na tela do CRM: resumo, barra de etapas, caminho entre
// unidades (diagrama horizontal da jornada), tarefas, linha do tempo, auditoria e histórico
// multiempresa. "Editar" abre o formulário de sempre (OpportunityDialog); "Encaminhar" leva o
// negócio para outra unidade (ForwardDialog); sem responsável, "Pegar para mim" fica com ele.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import StageProgress from '../conversation/StageProgress.vue';
import OpportunityActivity from '../activity/OpportunityActivity.vue';
import ForwardDialog from './ForwardDialog.vue';
import JourneyHistory from './JourneyHistory.vue';
import JourneyFlow from './JourneyFlow.vue';
import ConfirmDelete from './ConfirmDelete.vue';
import {
  claimOpportunity,
  crmState,
  markReceived,
  refreshContact,
} from '../crmStore';
import { useCrmChanges } from '../live';
import {
  STATUS_COLORS,
  errorMessage,
  formatDate,
  formatMoney,
} from '../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  pipelines: { type: Array, required: true },
});

const emit = defineEmits(['edit', 'changed']);

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const opportunity = ref(null);
const isSaving = ref(false);
const isClaiming = ref(false);
const forwardDialogRef = ref(null);
const confirmRef = ref(null);

const pipeline = computed(() =>
  props.pipelines.find(item => item.id === opportunity.value?.pipeline_id)
);
const unitName = computed(
  () =>
    props.access.units.find(
      unit => unit.id === opportunity.value?.business_unit_id
    )?.name || ''
);

// jornada deste negócio no histórico do contato (o JourneyHistory do rodapé carrega o histórico)
const history = computed(
  () => crmState.histories[opportunity.value?.contact.id]
);
const journey = computed(() =>
  history.value?.journeys.find(item =>
    item.opportunities.some(entry => entry.id === opportunity.value?.id)
  )
);
const showFlow = computed(
  () =>
    !!journey.value &&
    (journey.value.opportunities.length > 1 || !!journey.value.upcoming?.length)
);

// options.live: recarga porque alguém mudou o negócio; se ele sumiu (apagado), fecha sem erro
const refresh = async (options = {}) => {
  if (!opportunity.value) return;
  const { id } = opportunity.value;
  try {
    const { data } = await CrmAPI.getOpportunity(id);
    if (opportunity.value?.id === id) opportunity.value = data;
  } catch (error) {
    if (!options.live) useAlert(errorMessage(t, error));
    else if (error.response?.status === 404) opportunity.value = null;
  }
};

useCrmChanges(changes => {
  const id = opportunity.value?.id;
  if (
    id &&
    changes.some(
      change =>
        change.kind === 'reconnected' ||
        (change.kind === 'opportunity' && change.id === id) ||
        (change.kind === 'task' && change.opportunity_id === id)
    )
  ) {
    refresh({ live: true });
  }
});

const open = item => {
  opportunity.value = item;
  markReceived([item.id], true);
  refresh();
};

const close = () => {
  opportunity.value = null;
};

// negócio de outra unidade da mesma jornada (só os que o usuário enxerga têm link)
const openOther = async item => {
  try {
    const { data } = await CrmAPI.getOpportunity(item.id);
    opportunity.value = data;
    markReceived([data.id], true);
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const changed = async () => {
  await refresh();
  emit('changed');
};

const claim = async () => {
  isClaiming.value = true;
  const data = await claimOpportunity(t, opportunity.value);
  isClaiming.value = false;
  if (!data) return;
  opportunity.value = data;
  emit('changed');
  refreshContact(data.contact.id);
};

// depois de encaminhar, o painel mostra a origem (agora encaminhada) e o histórico atualizado
const forwarded = async () => {
  await changed();
  refreshContact(opportunity.value.contact.id);
};

// apagar fecha o painel e recarrega a lista; tarefas e linha do tempo saem junto
const askDelete = () => {
  const current = opportunity.value;
  confirmRef.value?.open(
    t('OUTSIDER_CRM.DELETE.OPPORTUNITY_TITLE'),
    t('OUTSIDER_CRM.DELETE.OPPORTUNITY_TEXT', {
      code: current.code,
      title: current.title,
    }),
    async () => {
      await CrmAPI.deleteOpportunity(current.id);
      close();
      emit('changed');
      refreshContact(current.contact.id);
    }
  );
};

const moveTo = async stage => {
  isSaving.value = true;
  try {
    await CrmAPI.updateOpportunity(opportunity.value.id, {
      stage_id: stage.id,
    });
    useAlert(t('OUTSIDER_CRM.CONVERSATION.MOVED', { stage: stage.name }));
    await changed();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

// Esc fecha o painel, menos quando um formulário (dialog) está aberto por cima
const onKeydown = event => {
  if (
    event.key === 'Escape' &&
    opportunity.value &&
    !document.querySelector('dialog[open]')
  ) {
    close();
  }
};

onMounted(() => document.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));

defineExpose({ open, refresh, close });
</script>

<template>
  <Teleport to="body">
    <div v-if="opportunity" class="fixed inset-0 z-50 flex justify-end">
      <div class="absolute inset-0 bg-n-alpha-black1" @click="close" />
      <aside
        class="relative flex flex-col w-full h-full max-w-2xl border-l shadow-xl bg-n-solid-1 border-n-weak"
      >
        <header
          class="flex items-start gap-3 px-5 pt-5 pb-4 border-b border-n-weak"
        >
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <div class="flex flex-wrap items-center gap-1.5 text-xs">
              <span
                class="px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11"
              >
                {{ opportunity.code }}
              </span>
              <span
                class="px-1.5 py-0.5 rounded-md"
                :class="STATUS_COLORS[opportunity.status]"
              >
                {{
                  t(`OUTSIDER_CRM.STATUS.${opportunity.status.toUpperCase()}`)
                }}
              </span>
              <span class="text-n-slate-11">
                {{ unitName }}
                <template v-if="pipeline">· {{ pipeline.name }}</template>
              </span>
            </div>
            <h2 class="mb-0 text-lg font-medium text-n-slate-12">
              {{ opportunity.title }}
            </h2>
            <div
              class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-n-slate-11"
            >
              <span class="inline-flex items-center gap-1.5 min-w-0">
                <Avatar
                  :name="opportunity.contact.name"
                  :src="opportunity.contact.thumbnail"
                  :size="18"
                  rounded-full
                />
                <span class="truncate">{{ opportunity.contact.name }}</span>
              </span>
              <router-link
                v-if="opportunity.conversation_display_id"
                :to="
                  accountScopedRoute('inbox_conversation', {
                    conversation_id: opportunity.conversation_display_id,
                  })
                "
                class="inline-flex items-center gap-1 text-n-blue-11 hover:underline"
              >
                <Icon icon="i-lucide-message-circle" class="size-3.5" />
                {{
                  t('OUTSIDER_CRM.DRAWER.OPEN_CONVERSATION', {
                    id: opportunity.conversation_display_id,
                  })
                }}
              </router-link>
            </div>
          </div>
          <Button
            type="button"
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :title="t('OUTSIDER_CRM.DRAWER.CLOSE')"
            @click="close"
          />
        </header>

        <div
          class="flex flex-col flex-1 min-h-0 gap-5 px-5 py-4 overflow-y-auto"
        >
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="flex flex-col gap-0.5">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.OPPORTUNITY.VALUE') }}
              </span>
              <span class="text-base font-semibold text-n-teal-11">
                {{ formatMoney(opportunity.value_cents) }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.OPPORTUNITY.CLOSE_DATE') }}
              </span>
              <span
                class="text-sm font-medium"
                :class="
                  opportunity.overdue ? 'text-n-ruby-11' : 'text-n-slate-12'
                "
              >
                {{ formatDate(opportunity.expected_close_on) || '—' }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.CONVERSATION.PROBABILITY') }}
              </span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ opportunity.effective_probability }}%
              </span>
            </div>
            <div class="flex flex-col gap-0.5 min-w-0">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.OPPORTUNITY.OWNER') }}
              </span>
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ opportunity.owner?.name || '—' }}
              </span>
            </div>
          </div>

          <StageProgress
            v-if="pipeline"
            :pipeline="pipeline"
            :stage-id="opportunity.stage_id"
            :status="opportunity.status"
            :can-move="opportunity.can_edit && !isSaving"
            @move="moveTo"
          />

          <div
            v-if="opportunity.can_claim"
            class="flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
          >
            <Icon icon="i-lucide-hand" class="size-4 shrink-0" />
            <span class="flex-1 min-w-0">
              {{ t('OUTSIDER_CRM.CLAIM.DRAWER_HINT') }}
            </span>
            <Button
              type="button"
              size="sm"
              icon="i-lucide-hand"
              :label="t('OUTSIDER_CRM.CLAIM.BUTTON_ME')"
              :is-loading="isClaiming"
              @click="claim"
            />
          </div>

          <p
            v-if="opportunity.forwarded_from"
            class="flex items-center gap-2 px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
          >
            <Icon icon="i-lucide-inbox" class="size-4 shrink-0" />
            {{
              t('OUTSIDER_CRM.FORWARD.RECEIVED_FROM', {
                unit: opportunity.forwarded_from.business_unit_name,
                code: opportunity.forwarded_from.code,
              })
            }}
          </p>
          <p
            v-if="opportunity.forwarded_to"
            class="flex items-center gap-2 px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
          >
            <Icon icon="i-lucide-forward" class="size-4 shrink-0" />
            {{
              t('OUTSIDER_CRM.FORWARD.SENT_TO', {
                unit: opportunity.forwarded_to.business_unit_name,
                code: opportunity.forwarded_to.code,
              })
            }}
          </p>

          <div class="flex flex-wrap gap-2">
            <Button
              type="button"
              size="sm"
              variant="faded"
              color="slate"
              :icon="opportunity.can_edit ? 'i-lucide-pencil' : 'i-lucide-eye'"
              :label="
                opportunity.can_edit
                  ? t('OUTSIDER_CRM.CONVERSATION.EDIT')
                  : t('OUTSIDER_CRM.CONVERSATION.VIEW')
              "
              @click="emit('edit', opportunity)"
            />
            <Button
              v-if="opportunity.can_forward"
              type="button"
              size="sm"
              variant="faded"
              color="amber"
              icon="i-lucide-forward"
              :label="t('OUTSIDER_CRM.FORWARD.BUTTON')"
              @click="forwardDialogRef?.open(opportunity)"
            />
            <Button
              v-if="opportunity.can_delete"
              type="button"
              size="sm"
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              :label="t('OUTSIDER_CRM.DELETE.OPPORTUNITY_BUTTON')"
              @click="askDelete"
            />
          </div>

          <section v-if="showFlow" class="flex flex-col gap-2">
            <div class="flex flex-col gap-0.5">
              <span
                class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
              >
                <Icon icon="i-lucide-route" class="size-4 text-n-slate-10" />
                {{ t('OUTSIDER_CRM.JOURNEY.TITLE') }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.JOURNEY.SUBTITLE') }}
              </span>
            </div>
            <JourneyFlow
              :journey="journey"
              :max-attempts="history.max_forward_attempts"
              :opportunity-id="opportunity.id"
              @open="openOther"
            />
          </section>

          <OpportunityActivity :opportunity="opportunity" @changed="changed" />

          <JourneyHistory
            :contact-id="opportunity.contact.id"
            :opportunity-id="opportunity.id"
            skip-current
            @open="openOther"
          />
        </div>
      </aside>
    </div>
    <ForwardDialog
      ref="forwardDialogRef"
      :unit-name="unitName"
      @forwarded="forwarded"
      @open="openOther"
    />
    <ConfirmDelete ref="confirmRef" />
  </Teleport>
</template>
