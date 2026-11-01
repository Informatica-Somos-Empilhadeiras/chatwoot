<script setup>
// OUTSIDER: no cabeçalho da conversa, quem está com ela, sempre à vista. Sem responsável:
// "Assumir". Com outro agente: "Solicitar transferência" (o mesmo pedido da busca, ver
// transfer/transferRequests.js) e, depois de pedir, "Aguardando..." com a opção de cancelar.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Avatar from 'next/avatar/Avatar.vue';
import {
  transferState,
  pendingRequestFor,
  requestTransfer,
  cancelTransfer,
} from 'dashboard/routes/dashboard/outsider/transfer/transferRequests';

const props = defineProps({
  chat: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();
const currentUserId = useMapGetter('getCurrentUserID');

const assignee = computed(() => props.chat.meta?.assignee || null);
const isBot = computed(() => props.chat.meta?.assignee_type === 'AgentBot');
const isMine = computed(
  () => !isBot.value && assignee.value?.id === currentUserId.value
);
const isOpen = computed(() => props.chat.status !== 'resolved');
const pending = computed(() => pendingRequestFor(props.chat.id));
const busy = computed(
  () =>
    !!transferState.busy[`conversation-${props.chat.id}`] ||
    (pending.value && !!transferState.busy[pending.value.id])
);

const canAskTransfer = computed(
  () => !isAdmin.value && !isMine.value && !isBot.value && !!assignee.value?.id
);

const takeOver = async () => {
  await store.dispatch('assignAgent', {
    conversationId: props.chat.id,
    agentId: currentUserId.value,
  });
  useAlert(t('OUTSIDER_WHATSAPP.LOOK.TAKEN'));
};

const ERRORS = ['not_assigned_to_other', 'not_found'];
const askTransfer = async () => {
  try {
    await requestTransfer(props.chat.id);
    useAlert(
      t('OUTSIDER_TOOLS.TRANSFER.REQUEST_SENT', { name: assignee.value.name })
    );
  } catch (error) {
    const code = error?.response?.data?.error;
    useAlert(
      ERRORS.includes(code)
        ? t(`OUTSIDER_TOOLS.TRANSFER.ERRORS.${code}`)
        : t('OUTSIDER_TOOLS.TRANSFER.ERRORS.generic')
    );
  }
};
const cancel = async () => {
  try {
    await cancelTransfer(pending.value.id);
  } catch (error) {
    useAlert(t('OUTSIDER_TOOLS.TRANSFER.ERRORS.generic'));
  }
};
</script>

<template>
  <div class="flex items-center gap-1.5 shrink-0" data-owner-pill>
    <span
      v-if="assignee?.id"
      v-tooltip.bottom="t('OUTSIDER_WHATSAPP.LOOK.OWNER_HINT')"
      class="inline-flex items-center gap-1.5 h-7 ltr:pl-0.5 ltr:pr-2.5 rtl:pr-0.5 rtl:pl-2.5 text-xs font-medium rounded-full max-w-44"
      :class="
        isMine
          ? 'bg-n-teal-3 text-n-teal-11'
          : isBot
            ? 'bg-n-iris-3 text-n-iris-11'
            : 'bg-n-alpha-2 text-n-slate-12'
      "
    >
      <span
        v-if="isBot"
        class="grid rounded-full size-6 place-items-center bg-n-iris-5"
      >
        <span class="i-lucide-bot size-3.5" />
      </span>
      <Avatar
        v-else
        :name="assignee.name || ''"
        :src="assignee.thumbnail || assignee.avatar_url || ''"
        :size="24"
        rounded-full
      />
      <span class="truncate">
        {{ isMine ? t('OUTSIDER_WHATSAPP.LOOK.WITH_YOU') : assignee.name }}
      </span>
    </span>
    <button
      v-else-if="isOpen"
      type="button"
      class="inline-flex items-center gap-1.5 h-7 px-2.5 text-xs font-semibold rounded-full bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4"
      @click="takeOver"
    >
      <span class="i-lucide-hand size-3.5" />
      {{ t('OUTSIDER_WHATSAPP.LOOK.TAKE') }}
    </button>

    <template v-if="canAskTransfer && isOpen">
      <button
        v-if="pending"
        type="button"
        v-tooltip.bottom="t('OUTSIDER_TOOLS.TRANSFER.CANCEL')"
        class="inline-flex items-center gap-1 h-7 px-2.5 text-xs font-medium rounded-full text-n-teal-11 bg-n-teal-3 hover:bg-n-teal-4"
        :disabled="busy"
        @click="cancel"
      >
        <span class="i-lucide-clock size-3.5" />
        {{ t('OUTSIDER_WHATSAPP.LOOK.WAITING_SHORT') }}
      </button>
      <button
        v-else
        type="button"
        class="inline-flex items-center gap-1 h-7 px-2.5 text-xs font-semibold rounded-full text-white bg-n-brand hover:opacity-90"
        :disabled="busy"
        @click="askTransfer"
      >
        <span class="i-lucide-arrow-right-left size-3.5" />
        {{ t('OUTSIDER_TOOLS.TRANSFER.ASK') }}
      </button>
    </template>
  </div>
</template>
