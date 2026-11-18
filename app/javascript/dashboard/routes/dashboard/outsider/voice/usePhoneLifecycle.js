// OUTSIDER: o que o telefone precisa enquanto a tela do Chatwoot (PhoneDock) ou a janela própria do telefone
// (PhoneWindow) está aberta (Entrega 23, separado na 24): liga o telefone ao entrar na conta, acompanha as
// mudanças em Telefonia > Configurações, avisa pelo navegador quando toca com a aba em segundo plano, mostra
// os avisos do telefone (gravação salva...) e pergunta antes de fechar no meio de uma ligação.
// OUTSIDER (push): o aviso de ligação tocando tem Atender e Recusar e vem do service worker; "Ligar de volta" do aviso
// de ligação perdida liga por aqui.
// Entrega 26: recebe os avisos do sussurro (convite, pedido para o cliente ouvir...) pelo canal ao vivo, também
// na janela própria do telefone.
// OUTSIDER (técnicos): Atender no aviso que acordou o celular (service worker, ou ?outsider_answer=id ao abrir) atende
// a ligação quando ela chegar; ?outsider_ring=id só a mostra tocando. No celular com o push ativo neste aparelho, a
// linha sai da central com o app escondido (logo no iPhone, que congela o app; uns segundos no Android) e volta ao
// abrir: as ligações chegam pelo aviso.
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
  answer,
  dial,
  expectCall,
  handleSignal,
  hangup,
  phone,
  restartPhone,
  sleepLine,
  startPhone,
  stopPhone,
  wakeLine,
} from './phone';

const SLEEP_AFTER = 20000;
const isMobileDevice = () =>
  /Android|iPhone|iPad|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isAppleDevice = () =>
  /iPhone|iPad|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

// este aparelho recebe o aviso de ligação (sem isso, dormir a linha faria a ligação não chegar)
const hasPush = async () => {
  if (
    !('serviceWorker' in navigator) ||
    !('Notification' in window) ||
    Notification.permission !== 'granted'
  )
    return false;
  try {
    const registration = await navigator.serviceWorker.getRegistration();
    return !!(await registration?.pushManager?.getSubscription());
  } catch {
    return false;
  }
};

export const usePhoneLifecycle = ({ popout = false } = {}) => {
  const { t } = useI18n();
  const { accountId } = useAccount();
  const { call, title, subtitle } = useCallInfo();

  // OUTSIDER (push): tocando com o Chatwoot em segundo plano, o aviso vem do service worker (o mesmo do push novo),
  // com os botões Atender e Recusar; ele só aparece se nenhuma aba do Chatwoot está na frente
  const worker = async message => {
    if (!('serviceWorker' in navigator)) return;
    try {
      const registration = await navigator.serviceWorker.getRegistration();
      registration?.active?.postMessage(message);
    } catch {
      // sem service worker: fica só a tela de ligação recebida
    }
  };

  let ringing = false;
  const closeNotification = () => {
    if (!ringing) return;
    ringing = false;
    worker({ type: 'outsider:call-stop' });
  };

  watch(
    () => [call.value?.state, title.value],
    ([state]) => {
      if (state !== 'ringing') {
        closeNotification();
        return;
      }
      if (!('Notification' in window) || Notification.permission !== 'granted')
        return;
      ringing = true;
      worker({
        type: 'outsider:call-ring',
        title: t('OUTSIDER_VOICE.CALL.NOTIFICATION', { name: title.value }),
        body: subtitle.value,
        person: title.value,
        photo: call.value?.lookup?.contact?.thumbnail || null,
        answer_label: t('OUTSIDER_VOICE.CALL.ANSWER'),
        decline_label: t('OUTSIDER_VOICE.CALL.REJECT'),
      });
    }
  );

  // clicou no aviso: Atender (traz o Chatwoot para frente), Recusar (a central passa para o próximo) ou só abrir
  const startDial = number => {
    let tries = 0;
    const attempt = () => {
      const error = dial(number);
      if (error === 'NOT_READY' && tries < 20) {
        tries += 1;
        setTimeout(attempt, 1000);
      } else if (error) {
        useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
      }
    };
    attempt();
  };

  const onWorkerMessage = event => {
    const data = event.data || {};
    // OUTSIDER (técnicos): Atender (ou tocar) no aviso da ligação que acordou o celular
    if (data.type === 'outsider:call-wake') {
      expectCall(data.linkedid, { answer: !!data.answer });
      wakeLine();
      return;
    }
    if (data.type === 'outsider:call') {
      if (data.action === 'answer') answer();
      else if (data.action === 'decline') hangup();
      return;
    }
    // "Ligar de volta" no aviso de ligação perdida
    if (data.type === 'outsider:push-open' && data.dial) startDial(data.dial);
  };
  if ('serviceWorker' in navigator) {
    useEventListener(navigator.serviceWorker, 'message', onWorkerMessage);
  }
  // "Ligar de volta" com o Chatwoot fechado: o aviso abre o Chatwoot com ?outsider_dial=número
  if (!popout) {
    const url = new URL(window.location.href);
    const pending = url.searchParams.get('outsider_dial');
    // OUTSIDER (técnicos): Atender (outsider_answer) ou tocar (outsider_ring) no aviso com o Chatwoot fechado
    const answerId = url.searchParams.get('outsider_answer');
    const ringId = url.searchParams.get('outsider_ring');
    ['outsider_dial', 'outsider_answer', 'outsider_ring'].forEach(key =>
      url.searchParams.delete(key)
    );
    if (pending || answerId || ringId) {
      window.history.replaceState(window.history.state, '', url.toString());
    }
    if (pending) startDial(pending);
    if (answerId || ringId) {
      expectCall(answerId || ringId, { answer: !!answerId });
    }
  }

  // OUTSIDER (técnicos): a linha dorme com o app escondido no celular (só com o push ativo aqui) e acorda ao abrir
  let sleepTimer = null;
  const cancelSleep = () => {
    clearTimeout(sleepTimer);
    sleepTimer = null;
  };
  const scheduleSleep = async () => {
    cancelSleep();
    if (popout || !isMobileDevice() || !document.hidden) return;
    if (!(await hasPush()) || !document.hidden) return;
    sleepTimer = setTimeout(
      () => {
        sleepTimer = null;
        if (document.hidden) sleepLine();
      },
      isAppleDevice() ? 0 : SLEEP_AFTER
    );
  };
  useEventListener(document, 'visibilitychange', () => {
    if (document.hidden) scheduleSleep();
    else {
      cancelSleep();
      wakeLine();
    }
  });
  // o Android congela a aba depois de um tempo escondida: sai da central antes
  useEventListener(document, 'freeze', () => {
    if (isMobileDevice()) sleepLine();
  });
  // ligação acabou com o app escondido: agora pode dormir
  watch(
    () => phone.call?.state,
    state => {
      if (document.hidden && (!state || state === 'ended')) scheduleSleep();
    }
  );

  // convite de colega para entrar na ligação dele, com a aba escondida: aviso do navegador
  watch(
    () => phone.invite?.at,
    () => {
      const { invite } = phone;
      if (
        !invite ||
        !document.hidden ||
        !('Notification' in window) ||
        Notification.permission !== 'granted'
      ) {
        return;
      }
      const alert = new Notification(
        t('OUTSIDER_VOICE.INVITE.NOTIFICATION', { name: invite.name }),
        { body: invite.customer, tag: 'outsider-invite' }
      );
      alert.onclick = () => {
        window.focus();
        alert.close();
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
    cancelSleep();
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
