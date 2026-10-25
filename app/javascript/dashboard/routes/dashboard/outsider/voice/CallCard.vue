<script setup>
// OUTSIDER: a ligação em andamento (Entrega 22), no alto da tela em qualquer página: quem liga (contato e
// negócio aberto, quando o número está cadastrado), atender ou recusar, mudo, teclado e encerrar. Também liga
// o telefone ao entrar na conta e avisa pelo navegador quando toca com a aba em segundo plano.
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useEventListener, useNow } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PhoneKeypad from './PhoneKeypad.vue';
import { formatPhone, formatDuration } from './format';
import {
  phone,
  startPhone,
  stopPhone,
  answer,
  hangup,
  toggleMute,
  sendDigit,
  clearEndedCall,
} from './phone';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const now = useNow({ interval: 1000 });

const showKeypad = ref(false);
let notification = null;

const call = computed(() => phone.call);
const contact = computed(() => call.value?.lookup?.contact);
const deal = computed(() => call.value?.lookup?.deal);
const isInternal = computed(() => (call.value?.number || '').length <= 4);

const title = computed(() => {
  if (!call.value) return '';
  if (contact.value) return contact.value.name;
  if (isInternal.value) {
    return (
      call.value.name ||
      t('OUTSIDER_VOICE.CALL.INTERNAL', { extension: call.value.number })
    );
  }
  return formatPhone(call.value.number);
});

const subtitle = computed(() => {
  if (!call.value) return '';
  if (isInternal.value) {
    return t('OUTSIDER_VOICE.CALL.INTERNAL', { extension: call.value.number });
  }
  if (contact.value) return formatPhone(call.value.number);
  return t('OUTSIDER_VOICE.CALL.UNKNOWN');
});

const stateLabel = computed(() => {
  const { state, endReason, answeredAt } = call.value;
  if (state === 'ended') return t(`OUTSIDER_VOICE.CALL.ENDED.${endReason}`);
  if (state === 'active') {
    return formatDuration((now.value.getTime() - answeredAt) / 1000);
  }
  return t(
    state === 'ringing'
      ? 'OUTSIDER_VOICE.CALL.INCOMING'
      : 'OUTSIDER_VOICE.CALL.DIALING'
  );
});

const openDeal = () =>
  router.push({
    path: frontendURL(`accounts/${accountId.value}/crm/opportunities`),
    query: { negocio: deal.value.id },
  });

const openConversation = () =>
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: call.value.lookup.conversation_id,
      })
    )
  );

const closeNotification = () => {
  notification?.close();
  notification = null;
};

// tocando com a aba escondida: aviso do navegador (se a pessoa já liberou notificações do Chatwoot)
watch(
  () => [call.value?.state, title.value],
  ([state]) => {
    if (state !== 'ringing') {
      closeNotification();
      return;
    }
    if (
      !document.hidden ||
      !('Notification' in window) ||
      Notification.permission !== 'granted'
    ) {
      return;
    }
    closeNotification();
    notification = new Notification(
      t('OUTSIDER_VOICE.CALL.NOTIFICATION', { name: title.value }),
      { body: subtitle.value, tag: 'outsider-call', requireInteraction: true }
    );
    notification.onclick = () => {
      window.focus();
      closeNotification();
    };
  }
);

watch(
  () => call.value?.state,
  () => {
    showKeypad.value = false;
  }
);

watch(accountId, id => id && startPhone(id), { immediate: true });
onBeforeUnmount(() => {
  closeNotification();
  stopPhone();
});

// recarregar ou fechar a aba derruba a ligação: o navegador pergunta antes
useEventListener(window, 'beforeunload', event => {
  if (!call.value || call.value.state === 'ended') return;
  event.preventDefault();
  event.returnValue = '';
});
</script>

<template>
  <div
    v-if="call"
    class="fixed z-[60] top-3 ltr:left-1/2 rtl:right-1/2 ltr:-translate-x-1/2 rtl:translate-x-1/2 w-[22rem] max-w-[calc(100vw-2rem)] flex flex-col gap-3 p-3 border shadow-lg rounded-xl border-n-weak bg-n-alpha-3 backdrop-blur-[100px]"
    data-testid="outsider-call-card"
  >
    <div class="flex items-center gap-3">
      <Avatar
        :size="40"
        :name="title"
        :src="contact?.thumbnail || ''"
        class="flex-shrink-0"
        :class="{ 'animate-pulse': call.state === 'ringing' }"
      />
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium truncate text-n-slate-12">
          {{ title }}
        </div>
        <div class="text-xs truncate text-n-slate-11">{{ subtitle }}</div>
        <div
          class="text-xs font-medium tabular-nums"
          :class="{
            'text-n-teal-11': call.state === 'active',
            'text-n-amber-11': ['ringing', 'dialing'].includes(call.state),
            'text-n-slate-11': call.state === 'ended',
          }"
          data-testid="outsider-call-state"
        >
          {{ stateLabel }}
        </div>
      </div>
      <Button
        v-if="call.state === 'ended'"
        xs
        ghost
        slate
        icon="i-lucide-x"
        :title="t('OUTSIDER_VOICE.CALL.CLOSE')"
        @click="clearEndedCall"
      />
    </div>

    <div
      v-if="deal || call.lookup?.conversation_id"
      class="flex flex-wrap items-center gap-1.5"
    >
      <button
        v-if="deal"
        type="button"
        class="flex items-center min-w-0 gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
        :title="t('OUTSIDER_VOICE.CALL.OPEN_DEAL')"
        @click="openDeal"
      >
        <span class="flex-shrink-0 i-lucide-kanban size-3.5 text-n-slate-11" />
        <span class="truncate">
          {{
            t('OUTSIDER_VOICE.CALL.DEAL', {
              title: deal.title,
              stage: deal.stage,
            })
          }}
        </span>
      </button>
      <button
        v-if="call.lookup?.conversation_id"
        type="button"
        class="flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
        @click="openConversation"
      >
        <span
          class="flex-shrink-0 i-lucide-message-circle size-3.5 text-n-slate-11"
        />
        {{ t('OUTSIDER_VOICE.CALL.OPEN_CONVERSATION') }}
      </button>
    </div>

    <PhoneKeypad
      v-if="showKeypad && call.state === 'active'"
      @press="sendDigit"
    />

    <div v-if="call.state === 'ringing'" class="grid grid-cols-2 gap-2">
      <Button
        sm
        ruby
        icon="i-lucide-phone-off"
        :label="t('OUTSIDER_VOICE.CALL.REJECT')"
        data-testid="outsider-call-reject"
        @click="hangup"
      />
      <Button
        sm
        teal
        icon="i-lucide-phone"
        :label="t('OUTSIDER_VOICE.CALL.ANSWER')"
        data-testid="outsider-call-answer"
        @click="answer"
      />
    </div>
    <div
      v-else-if="call.state !== 'ended'"
      class="flex items-center justify-end gap-2"
    >
      <template v-if="call.state === 'active'">
        <Button
          sm
          :variant="call.muted ? 'solid' : 'faded'"
          :color="call.muted ? 'amber' : 'slate'"
          :icon="call.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
          :label="
            call.muted
              ? t('OUTSIDER_VOICE.CALL.UNMUTE')
              : t('OUTSIDER_VOICE.CALL.MUTE')
          "
          data-testid="outsider-call-mute"
          @click="toggleMute"
        />
        <Button
          sm
          faded
          slate
          icon="i-lucide-grid-3x3"
          :title="t('OUTSIDER_VOICE.CALL.KEYPAD')"
          @click="showKeypad = !showKeypad"
        />
      </template>
      <Button
        sm
        ruby
        icon="i-lucide-phone-off"
        :label="t('OUTSIDER_VOICE.CALL.HANGUP')"
        data-testid="outsider-call-hangup"
        @click="hangup"
      />
    </div>
  </div>
</template>
