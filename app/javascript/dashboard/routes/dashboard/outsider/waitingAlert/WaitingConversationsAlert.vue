<script setup>
// OUTSIDER: aviso para os agentes quando há cliente esperando sem ninguém atribuído
// (aba Esperando). Mostra uma janela com as conversas e o botão "Assumir", toca um som
// e muda o título da aba do navegador. Só para agentes com status Online; os
// administradores não recebem. Os tempos ficam em config.js.
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useDocumentVisibility, useIntervalFn } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { phone } from '../voice/phone';
import {
  ALERT_AFTER,
  REMIND_EVERY,
  POLL_EVERY,
  LATE_AFTER,
  MAX_LISTED,
  SOUND_URL,
  SHOW_WAITING_TAB_EVENT,
} from './config';

const { t } = useI18n();
const router = useRouter();
const { isAdmin } = useAdmin();
const visibility = useDocumentVisibility();

const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');
const availability = useMapGetter('getCurrentUserAvailability');
const getInbox = useMapGetter('inboxes/getInbox');

const dialogRef = ref(null);
const isOpen = ref(false);
const conversations = ref([]);
const total = ref(0);
const now = ref(Date.now());
const takingId = ref(null);
let snoozedUntil = 0;
let closingByCode = false;

const isEnabled = computed(
  () => !!accountId.value && !isAdmin.value && availability.value === 'online'
);

const nowInSeconds = () => Math.floor(now.value / 1000);

// waiting_since é quando o cliente mandou a mensagem que ainda não foi respondida.
// Sem ele, alguém já respondeu (ex.: conversa aberta por um agente), então não avisa.
const waitingSeconds = conversation =>
  nowInSeconds() - conversation.waiting_since;

const overdue = computed(() =>
  conversations.value.filter(
    c => c.waiting_since && waitingSeconds(c) >= ALERT_AFTER
  )
);
const waitingCount = computed(() =>
  Math.max(total.value, overdue.value.length)
);
const listed = computed(() => overdue.value.slice(0, MAX_LISTED));
const hiddenCount = computed(() => waitingCount.value - listed.value.length);

const waitingLabel = conversation => {
  const minutes = Math.floor(waitingSeconds(conversation) / 60);
  if (minutes < 60) {
    return t('CHAT_LIST.OUTSIDER_WAITING.MINUTES', { count: minutes }, minutes);
  }
  return t('CHAT_LIST.OUTSIDER_WAITING.HOURS', {
    hours: Math.floor(minutes / 60),
    minutes: minutes % 60,
  });
};

const inboxName = conversation => getInbox.value(conversation.inbox_id)?.name;

const playSound = () => {
  new Audio(SOUND_URL).play().catch(() => {});
};

const open = () => {
  isOpen.value = true;
  dialogRef.value?.open();
  playSound();
};

const closeByCode = () => {
  if (!isOpen.value) return;
  closingByCode = true;
  dialogRef.value?.close();
};

// fechado pelo agente ("Agora não", Esc ou clique fora): volta depois de REMIND_EVERY
const onClose = () => {
  isOpen.value = false;
  if (!closingByCode) snoozedUntil = Date.now() + REMIND_EVERY * 1000;
  closingByCode = false;
};

const refresh = async () => {
  if (!isEnabled.value) return;
  try {
    const { data } = await ConversationAPI.get({
      assigneeType: 'unassigned',
      status: 'open',
      sortBy: 'waiting_since_asc',
      page: 1,
    });
    conversations.value = data.data.payload;
    total.value = data.data.meta.unassigned_count;
    now.value = Date.now();
  } catch {
    // sem rede: tenta de novo na próxima volta
  }
};

const { pause, resume } = useIntervalFn(refresh, POLL_EVERY * 1000, {
  immediate: false,
});

watch(
  isEnabled,
  enabled => {
    if (enabled) {
      refresh();
      resume();
    } else {
      pause();
      conversations.value = [];
      closeByCode();
    }
  },
  { immediate: true }
);

watch(visibility, value => {
  if (value === 'visible') refresh();
});

// em ligação pelo telefone do CRM o aviso espera: aberto, ele travaria a tela e o botão de atender
const inCall = computed(() => phone.call && phone.call.state !== 'ended');

watch(overdue, list => {
  if (!list.length) closeByCode();
  else if (!isOpen.value && !inCall.value && Date.now() >= snoozedUntil) {
    open();
  }
});

watch(inCall, value => {
  if (value) closeByCode();
  else if (overdue.value.length && Date.now() >= snoozedUntil) open();
});

// com a aba do navegador em segundo plano, o título pisca com o número de clientes esperando
let titleBeforeBlink = '';
const { pause: stopBlink, resume: startBlink } = useIntervalFn(
  () => {
    const alertTitle = t('CHAT_LIST.OUTSIDER_WAITING.TAB_TITLE', {
      count: overdue.value.length,
    });
    document.title =
      document.title === alertTitle ? titleBeforeBlink : alertTitle;
  },
  1500,
  { immediate: false }
);

const restoreTitle = () => {
  if (!titleBeforeBlink) return;
  stopBlink();
  document.title = titleBeforeBlink;
  titleBeforeBlink = '';
};

watch(
  () => overdue.value.length > 0 && visibility.value === 'hidden',
  shouldBlink => {
    if (!shouldBlink) {
      restoreTitle();
    } else if (!titleBeforeBlink) {
      titleBeforeBlink = document.title;
      startBlink();
    }
  }
);

onBeforeUnmount(restoreTitle);

const openConversation = id =>
  router.push(frontendURL(conversationUrl({ accountId: accountId.value, id })));

// outro agente pode ter assumido segundos antes: confere antes de atribuir
const take = async conversation => {
  takingId.value = conversation.id;
  try {
    const { data } = await ConversationAPI.show(conversation.id);
    const assignee = data.meta?.assignee;
    if (assignee && assignee.id !== currentUser.value.id) {
      useAlert(
        t('CHAT_LIST.OUTSIDER_WAITING.ALREADY_TAKEN', { name: assignee.name })
      );
    } else {
      await ConversationAPI.assignAgent({
        conversationId: conversation.id,
        agentId: currentUser.value.id,
      });
      closeByCode();
      openConversation(conversation.id);
    }
  } catch {
    useAlert(t('CHAT_LIST.OUTSIDER_WAITING.TAKE_ERROR'));
  } finally {
    takingId.value = null;
    refresh();
  }
};

const showWaitingTab = async () => {
  closeByCode();
  snoozedUntil = Date.now() + REMIND_EVERY * 1000;
  await router.push(frontendURL(`accounts/${accountId.value}/dashboard`));
  await nextTick();
  emitter.emit(SHOW_WAITING_TAB_EVENT);
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    position="top"
    width="md"
    :title="
      t(
        'CHAT_LIST.OUTSIDER_WAITING.TITLE',
        { count: waitingCount },
        waitingCount
      )
    "
    :description="t('CHAT_LIST.OUTSIDER_WAITING.DESCRIPTION')"
    @close="onClose"
  >
    <ul class="flex flex-col gap-2 !m-0 list-none">
      <li
        v-for="conversation in listed"
        :key="conversation.id"
        class="flex items-center gap-3 p-2.5 rounded-lg bg-n-alpha-1 border border-n-weak"
      >
        <Avatar
          :name="conversation.meta.sender.name || ''"
          :src="conversation.meta.sender.thumbnail"
          :size="36"
          rounded-full
        />
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ conversation.meta.sender.name }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{ inboxName(conversation) }}
          </span>
          <span
            class="text-xs font-medium"
            :class="
              waitingSeconds(conversation) >= LATE_AFTER
                ? 'text-n-ruby-11'
                : 'text-n-amber-11'
            "
          >
            {{ waitingLabel(conversation) }}
          </span>
        </div>
        <Button
          sm
          :label="t('CHAT_LIST.OUTSIDER_WAITING.TAKE')"
          :is-loading="takingId === conversation.id"
          :disabled="!!takingId"
          type="button"
          @click="take(conversation)"
        />
      </li>
    </ul>
    <p v-if="hiddenCount > 0" class="mb-0 text-xs text-center text-n-slate-11">
      {{ t('CHAT_LIST.OUTSIDER_WAITING.MORE', { count: hiddenCount }) }}
    </p>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="t('CHAT_LIST.OUTSIDER_WAITING.LATER')"
          class="w-full"
          type="button"
          @click="dialogRef.close()"
        />
        <Button
          :label="t('CHAT_LIST.OUTSIDER_WAITING.VIEW_ALL')"
          class="w-full"
          type="button"
          @click="showWaitingTab"
        />
      </div>
    </template>
  </Dialog>
</template>
