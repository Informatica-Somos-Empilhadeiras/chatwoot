// OUTSIDER (técnicos): o aviso de ligação deste aparelho (push). Usado no Perfil e no lembrete do Teclado: diz se está
// ativo, desligado, bloqueado ou se o iPhone precisa instalar o app antes, e ativa/testa com um toque.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import OutsiderPushAPI from 'dashboard/api/outsider/push';
import {
  activatePush,
  isAppleMobile,
  isSupported,
  loadPush,
  pushState,
  syncDevice,
} from '../../push/pushDevice';
import { installState } from './installPrompt';

const subscribed = ref(null);

const checkSubscription = async () => {
  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    subscribed.value = !!(await registration?.pushManager?.getSubscription());
  } catch {
    subscribed.value = false;
  }
};

export const useTechPush = () => {
  const { t } = useI18n();
  const working = ref(false);
  const apple = isAppleMobile();

  const pushStatus = computed(() => {
    if (!isSupported())
      return apple && !installState.installed ? 'INSTALL_FIRST' : 'UNSUPPORTED';
    if (pushState.permission === 'denied') return 'BLOCKED';
    if (subscribed.value === null) return 'CHECKING';
    if (pushState.permission === 'granted' && subscribed.value) return 'ACTIVE';
    return 'OFF';
  });

  onMounted(async () => {
    if (!isSupported()) return;
    try {
      await loadPush();
    } catch {
      // sem resposta: o botão Ativar continua funcionando
    }
    await checkSubscription();
  });

  const enablePush = async () => {
    working.value = true;
    try {
      const ok = await activatePush();
      if (ok) await syncDevice().catch(() => {});
      await checkSubscription();
      useAlert(
        t(
          ok
            ? 'OUTSIDER_VOICE.TECH.PUSH.ENABLED'
            : 'OUTSIDER_VOICE.TECH.PUSH.REFUSED'
        )
      );
    } catch {
      useAlert(t('OUTSIDER_VOICE.TECH.PUSH.FAILED'));
    } finally {
      working.value = false;
    }
  };

  const testPush = async () => {
    try {
      await OutsiderPushAPI.test();
      useAlert(t('OUTSIDER_VOICE.TECH.PUSH.TEST_SENT'));
    } catch {
      useAlert(t('OUTSIDER_VOICE.TECH.PUSH.FAILED'));
    }
  };

  return { pushStatus, working, enablePush, testPush, apple };
};
