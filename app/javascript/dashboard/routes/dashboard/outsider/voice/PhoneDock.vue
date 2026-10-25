<script setup>
// OUTSIDER: o telefone na tela, em qualquer página (Entrega 23): aberto e fixo no canto (PhonePanel) ou,
// minimizado, só o cartão da ligação (CallMini). Também liga o telefone ao entrar na conta, acompanha as
// mudanças em Telefonia > Configurações, avisa pelo navegador quando toca com a aba em segundo plano e
// pergunta antes de fechar a aba no meio de uma ligação.
import { watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import PhonePanel from './PhonePanel.vue';
import CallMini from './CallMini.vue';
import { useCallInfo } from './useCallInfo';
import { onCrmChange } from '../crm/live';
import {
  CENTRAL_SYNC_WAIT,
  panel,
  phone,
  restartPhone,
  startPhone,
  stopPhone,
} from './phone';

const { t } = useI18n();
const { accountId } = useAccount();
const { call, title, subtitle } = useCallInfo();

let notification = null;

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

watch(accountId, id => id && startPhone(id), { immediate: true });

// Telefonia > Configurações salvas (ramal ligado, trocado ou desligado): o telefone busca o ramal de novo
// quando a central já tiver a configuração nova
let settingsTimer = null;
const stopFollowingSettings = onCrmChange(changes => {
  if (!changes.some(({ kind }) => kind === 'voice')) return;
  clearTimeout(settingsTimer);
  settingsTimer = setTimeout(restartPhone, CENTRAL_SYNC_WAIT);
});

onBeforeUnmount(() => {
  stopFollowingSettings();
  clearTimeout(settingsTimer);
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
  <PhonePanel v-if="panel.open && phone.status !== 'off'" />
  <CallMini v-else-if="call" />
</template>
