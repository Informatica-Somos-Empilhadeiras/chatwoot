// OUTSIDER: o que a tela mostra da ligação em andamento (Entrega 23), usado pelo painel do telefone e pelo
// cartão minimizado: quem é (contato cadastrado, ramal ou o número), situação com o tempo de conversa e os
// atalhos para o negócio e a conversa do cliente.
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { phone } from './phone';
import { formatPhone, formatDuration } from './format';

export const useCallInfo = () => {
  const { t } = useI18n();
  const router = useRouter();
  const { accountId } = useAccount();
  const now = useNow({ interval: 1000 });

  const call = computed(() => phone.call);
  const contact = computed(() => call.value?.lookup?.contact);
  const deal = computed(() => call.value?.lookup?.deal);
  const conversationId = computed(() => call.value?.lookup?.conversation_id);
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
      return t('OUTSIDER_VOICE.CALL.INTERNAL', {
        extension: call.value.number,
      });
    }
    if (contact.value) return formatPhone(call.value.number);
    return t('OUTSIDER_VOICE.CALL.UNKNOWN');
  });

  const stateLabel = computed(() => {
    if (!call.value) return '';
    const { state, endReason, answeredAt, held, transferTo } = call.value;
    if (state === 'ended') {
      return t(`OUTSIDER_VOICE.CALL.ENDED.${endReason}`, {
        extension: transferTo,
      });
    }
    if (state === 'active') {
      const time = formatDuration((now.value.getTime() - answeredAt) / 1000);
      return held ? t('OUTSIDER_VOICE.CALL.ON_HOLD', { time }) : time;
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
          id: conversationId.value,
        })
      )
    );

  return {
    call,
    contact,
    deal,
    conversationId,
    title,
    subtitle,
    stateLabel,
    openDeal,
    openConversation,
  };
};
