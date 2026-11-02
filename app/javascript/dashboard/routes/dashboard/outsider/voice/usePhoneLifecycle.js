// OUTSIDER: o que o telefone precisa enquanto a tela do Chatwoot (PhoneDock) ou a janela própria do telefone
// (PhoneWindow) está aberta (Entrega 23, separado na 24): liga o telefone ao entrar na conta, acompanha as
// mudanças em Telefonia > Configurações, avisa pelo navegador quando toca com a aba em segundo plano, mostra
// os avisos do telefone (gravação salva...) e pergunta antes de fechar no meio de uma ligação.
// Entrega 26: recebe os avisos do sussurro (convite, pedido para o cliente ouvir...) pelo canal ao vivo, também
// na janela própria do telefone.
import { watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCallInfo } from './useCallInfo';
import { onCrmChange, onVoiceSignal, startLiveUpdates } from '../crm/live';
import { ensureCrmContext } from '../crm/crmStore';
import {
  CENTRAL_SYNC_WAIT,
  handleSignal,
  phone,
  restartPhone,
  startPhone,
  stopPhone,
} from './phone';

export const usePhoneLifecycle = ({ popout = false } = {}) => {
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

  // avisos do telefone (a gravação vai para a ligação no fim dela)
  watch(
    () => phone.notice?.at,
    () => {
      if (phone.notice && !document.hidden) {
        useAlert(
          t(
            `OUTSIDER_VOICE.NOTICES.${phone.notice.code}`,
            phone.notice.params || {}
          )
        );
      }
    }
  );

  watch(accountId, id => id && startPhone(id, { popout }), {
    immediate: true,
  });

  // o canal ao vivo e o acesso ao CRM (vincular negócio) também na janela própria do telefone; na do Chatwoot já
  // vêm pelo CRM e não abrem duas vezes
  watch(
    () => [accountId.value, phone.status !== 'off'],
    ([id, on]) => {
      if (!id || !on) return;
      startLiveUpdates(String(id));
      ensureCrmContext();
    },
    { immediate: true }
  );
  const stopSignals = onVoiceSignal(handleSignal);

  // Telefonia > Configurações salvas (ramal ligado, trocado ou desligado): o telefone busca o ramal de novo
  // quando a central já tiver a configuração nova
  let settingsTimer = null;
  const stopFollowingSettings = onCrmChange(changes => {
    if (!changes.some(({ kind }) => kind === 'voice')) return;
    clearTimeout(settingsTimer);
    settingsTimer = setTimeout(restartPhone, CENTRAL_SYNC_WAIT);
  });

  onBeforeUnmount(() => {
    stopSignals();
    stopFollowingSettings();
    clearTimeout(settingsTimer);
    closeNotification();
    stopPhone();
  });

  // recarregar ou fechar a aba que está com a linha derruba a ligação: o navegador pergunta antes
  useEventListener(window, 'beforeunload', event => {
    if (!phone.holder || !call.value || call.value.state === 'ended') return;
    event.preventDefault();
    event.returnValue = '';
  });
};
