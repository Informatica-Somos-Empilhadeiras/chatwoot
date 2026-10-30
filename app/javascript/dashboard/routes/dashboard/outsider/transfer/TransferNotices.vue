<script setup>
// OUTSIDER: avisos de transferência de conversa (transferRequests.js).
//  - quem está com a conversa: cartão no canto com Aceitar, Recusar e Ver, até responder
//    (dá para recolher numa pílula, sem sumir)
//  - quem pediu e foi recusado: cartão com OK, até clicar
//  - quem pediu e foi aceito: janela que some sozinha depois de alguns segundos
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useDocumentVisibility, useIntervalFn } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { timeAgo } from 'dashboard/helper/outsider/timeAgo';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  NOTICE_EVENT,
  transferState,
  applyTransferNotice,
  fetchTransfers,
  acceptTransfer,
  declineTransfer,
  acknowledgeTransfer,
} from './transferRequests';

const POLL_EVERY = 90 * 1000;
const ACCEPTED_VISIBLE_FOR = 6;

const { t, locale } = useI18n();
const router = useRouter();
const visibility = useDocumentVisibility();
const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');

const collapsed = ref(false);
const decliningId = ref(null);
const declineNote = ref('');
const countdown = ref(ACCEPTED_VISIBLE_FOR);
let countdownTimer = null;

const incoming = computed(() => transferState.incoming);
const declined = computed(() =>
  transferState.answered.filter(request => request.status === 'declined')
);
const accepted = computed(
  () =>
    transferState.answered.find(request => request.status === 'accepted') ||
    null
);
const cardCount = computed(() => incoming.value.length + declined.value.length);

const load = async () => {
  if (!accountId.value) return;
  try {
    await fetchTransfers();
  } catch {
    // sem rede agora: tenta de novo no próximo ciclo
  }
};

const onNotice = data => {
  if (data?.kind !== 'transfer_request') return;
  applyTransferNotice(data.action, data.request, currentUserId.value);
  if (
    data.action === 'created' &&
    data.request?.holder?.id === currentUserId.value
  ) {
    collapsed.value = false;
  }
};

const conversationPath = request =>
  frontendURL(
    conversationUrl({ accountId: accountId.value, id: request.conversation.id })
  );

const openConversation = request => {
  if (request?.conversation?.id)
    router.push({ path: conversationPath(request) });
};

const errorText = error => {
  const code = error?.response?.data?.error;
  return ['conversation_changed', 'already_answered'].includes(code)
    ? t(`OUTSIDER_TOOLS.TRANSFER.ERRORS.${code}`)
    : t('OUTSIDER_TOOLS.TRANSFER.ERRORS.generic');
};

const accept = async request => {
  try {
    await acceptTransfer(request.id);
    useAlert(
      t('OUTSIDER_TOOLS.TRANSFER.ACCEPTED_BY_ME', {
        name: request.requester.name,
        contact: request.contact?.name,
      })
    );
  } catch (error) {
    useAlert(errorText(error));
  }
};

const startDecline = request => {
  decliningId.value = request.id;
  declineNote.value = '';
};

const confirmDecline = async request => {
  try {
    await declineTransfer(request.id, declineNote.value.trim());
    decliningId.value = null;
  } catch (error) {
    useAlert(errorText(error));
  }
};

const acknowledge = request => {
  acknowledgeTransfer(request.id).catch(() => {});
};

// aceito: janela com contagem; ao fechar (ou acabar o tempo) marca como visto
const stopCountdown = () => {
  clearInterval(countdownTimer);
  countdownTimer = null;
};

const closeAccepted = () => {
  stopCountdown();
  if (accepted.value) acknowledge(accepted.value);
};

const openAccepted = () => {
  const request = accepted.value;
  closeAccepted();
  openConversation(request);
};

watch(
  () => accepted.value?.id,
  id => {
    stopCountdown();
    if (!id) return;
    countdown.value = ACCEPTED_VISIBLE_FOR;
    countdownTimer = setInterval(() => {
      countdown.value -= 1;
      if (countdown.value <= 0) closeAccepted();
    }, 1000);
  },
  { immediate: true }
);

useIntervalFn(() => {
  if (visibility.value === 'visible') load();
}, POLL_EVERY);

watch(accountId, load);

onMounted(() => {
  load();
  emitter.on(NOTICE_EVENT, onNotice);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, load);
});

onBeforeUnmount(() => {
  stopCountdown();
  emitter.off(NOTICE_EVENT, onNotice);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, load);
});
</script>

<template>
  <div
    v-if="cardCount"
    class="fixed z-[60] flex flex-col items-end gap-2 top-16 ltr:right-4 rtl:left-4 w-[22rem] max-w-[calc(100vw-2rem)] pointer-events-none"
  >
    <button
      v-if="collapsed"
      type="button"
      class="flex items-center gap-2 px-3 py-2 text-sm font-medium border rounded-full shadow-lg pointer-events-auto bg-n-solid-2 border-n-weak text-n-slate-12 hover:bg-n-solid-3"
      @click="collapsed = false"
    >
      <span class="relative flex size-2">
        <span
          class="absolute inline-flex w-full h-full rounded-full opacity-75 animate-ping bg-n-brand"
        />
        <span class="relative inline-flex rounded-full size-2 bg-n-brand" />
      </span>
      {{ t('OUTSIDER_TOOLS.TRANSFER.PILL', { count: cardCount }, cardCount) }}
    </button>

    <template v-else>
      <!-- pedidos para mim -->
      <div
        v-for="request in incoming"
        :key="`in-${request.id}`"
        class="w-full p-3 border shadow-lg pointer-events-auto rounded-xl bg-n-solid-2 border-n-brand/40 outsider-transfer-card"
      >
        <div class="flex items-start gap-3">
          <Avatar
            :name="request.requester.name"
            :src="request.requester.thumbnail"
            :size="32"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <p class="text-sm leading-5 text-n-slate-12">
              <span class="font-semibold">{{ request.requester.name }}</span>
              {{ t('OUTSIDER_TOOLS.TRANSFER.ASKS_FOR') }}
              <span class="font-semibold">{{ request.contact?.name }}</span>
            </p>
            <p
              v-if="request.note"
              class="px-2 py-1 text-xs italic rounded-md bg-n-alpha-1 text-n-slate-11"
            >
              {{ `“${request.note}”` }}
            </p>
            <span class="text-xs text-n-slate-10">
              {{ timeAgo(request.created_at, locale) }}
            </span>
          </div>
          <button
            type="button"
            class="p-1 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
            :title="t('OUTSIDER_TOOLS.TRANSFER.MINIMIZE')"
            @click="collapsed = true"
          >
            <Icon icon="i-lucide-minus" class="size-4" />
          </button>
        </div>

        <div v-if="decliningId === request.id" class="flex flex-col gap-2 mt-3">
          <input
            v-model="declineNote"
            type="text"
            maxlength="500"
            class="w-full !mb-0 text-sm"
            :placeholder="t('OUTSIDER_TOOLS.TRANSFER.DECLINE_REASON')"
            @keydown.enter.prevent="confirmDecline(request)"
          />
          <div class="flex justify-end gap-2">
            <Button
              :label="t('OUTSIDER_TOOLS.TRANSFER.BACK')"
              xs
              ghost
              slate
              @click="decliningId = null"
            />
            <Button
              :label="t('OUTSIDER_TOOLS.TRANSFER.DECLINE')"
              xs
              ruby
              :is-loading="!!transferState.busy[request.id]"
              @click="confirmDecline(request)"
            />
          </div>
        </div>
        <div v-else class="flex items-center justify-end gap-2 mt-3">
          <Button
            :label="t('OUTSIDER_TOOLS.TRANSFER.VIEW')"
            icon="i-lucide-external-link"
            xs
            ghost
            slate
            @click="openConversation(request)"
          />
          <Button
            :label="t('OUTSIDER_TOOLS.TRANSFER.DECLINE')"
            xs
            faded
            slate
            :disabled="!!transferState.busy[request.id]"
            @click="startDecline(request)"
          />
          <Button
            :label="t('OUTSIDER_TOOLS.TRANSFER.ACCEPT')"
            icon="i-lucide-check"
            xs
            :is-loading="!!transferState.busy[request.id]"
            @click="accept(request)"
          />
        </div>
      </div>

      <!-- meus pedidos recusados -->
      <div
        v-for="request in declined"
        :key="`no-${request.id}`"
        class="w-full p-3 border shadow-lg pointer-events-auto rounded-xl bg-n-solid-2 border-n-ruby-6"
      >
        <div class="flex items-start gap-3">
          <span
            class="flex items-center justify-center rounded-full size-8 shrink-0 bg-n-ruby-3 text-n-ruby-11"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <p class="text-sm leading-5 text-n-slate-12">
              <span class="font-semibold">{{ request.holder.name }}</span>
              {{ t('OUTSIDER_TOOLS.TRANSFER.DECLINED_FOR') }}
              <span class="font-semibold">{{ request.contact?.name }}</span>
            </p>
            <p
              v-if="request.note"
              class="px-2 py-1 text-xs italic rounded-md bg-n-alpha-1 text-n-slate-11"
            >
              {{ `“${request.note}”` }}
            </p>
          </div>
        </div>
        <div class="flex justify-end mt-3">
          <Button
            :label="t('OUTSIDER_TOOLS.TRANSFER.OK')"
            xs
            :is-loading="!!transferState.busy[request.id]"
            @click="acknowledge(request)"
          />
        </div>
      </div>
    </template>
  </div>

  <!-- meu pedido aceito: some sozinho -->
  <Teleport to="body">
    <div
      v-if="accepted"
      class="fixed inset-0 z-[70] flex items-center justify-center bg-n-alpha-black1/40"
      @click.self="closeAccepted"
    >
      <div
        class="flex flex-col items-center w-[22rem] max-w-[calc(100vw-2rem)] gap-3 p-6 text-center shadow-2xl rounded-2xl bg-n-solid-2 outsider-transfer-accepted"
      >
        <span
          class="flex items-center justify-center rounded-full size-14 bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-check" class="size-7" />
        </span>
        <p class="text-base font-semibold text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.TRANSFER.ACCEPTED_TITLE') }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{
            t('OUTSIDER_TOOLS.TRANSFER.ACCEPTED_TEXT', {
              name: accepted.holder.name,
              contact: accepted.contact?.name,
            })
          }}
        </p>
        <div class="flex gap-2 mt-1">
          <Button
            :label="
              t('OUTSIDER_TOOLS.TRANSFER.CLOSE_IN', { seconds: countdown })
            "
            sm
            faded
            slate
            @click="closeAccepted"
          />
          <Button
            :label="t('OUTSIDER_TOOLS.TRANSFER.OPEN_CONVERSATION')"
            sm
            @click="openAccepted"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.outsider-transfer-card {
  animation: outsider-transfer-in 0.35s ease-out;
}

.outsider-transfer-accepted {
  animation: outsider-transfer-pop 0.25s ease-out;
}

@keyframes outsider-transfer-in {
  from {
    opacity: 0;
    transform: translateY(-8px);
  }
}

@keyframes outsider-transfer-pop {
  from {
    opacity: 0;
    transform: scale(0.94);
  }
}
</style>
