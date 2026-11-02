// OUTSIDER: o que a tela mostra da ligação em andamento (Entrega 23), usado pelo painel do telefone e pelo
// cartão minimizado: quem é (contato cadastrado, ramal ou o número), situação com o tempo de conversa e os
// atalhos para o negócio e a conversa do cliente. Entrega 24: o mesmo para cada pessoa da conferência.
// Entrega 26: o cadastro do cliente, o negócio vinculado, por onde passou na URA e as monitorias (quem é o
// atendente ouvido ou com quem se sussurra).
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { phone, isPopoutWindow } from './phone';
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
  const deals = computed(() => call.value?.lookup?.deals || []);
  const linkedDeal = computed(() => call.value?.deal || null);
  const ivr = computed(() => call.value?.lookup?.ivr || null);
  const monitor = computed(() => call.value?.monitor || null);

  // nome e segunda linha de uma pessoa da ligação (a principal ou alguém da conferência)
  const nameOf = party => {
    if (!party) return '';
    if (party.monitor) {
      return (
        party.monitor.name ||
        t('OUTSIDER_VOICE.CALL.INTERNAL', {
          extension: party.monitor.extension,
        })
      );
    }
    const internal = (party.number || '').length <= 4;
    if (party.lookup?.contact) return party.lookup.contact.name;
    if (internal) {
      return (
        party.name ||
        t('OUTSIDER_VOICE.CALL.INTERNAL', { extension: party.number })
      );
    }
    return formatPhone(party.number);
  };

  const detailOf = party => {
    if (!party) return '';
    if (party.monitor) {
      return party.monitor.customer
        ? t('OUTSIDER_VOICE.MONITOR.WITH', {
            customer: party.monitor.customer,
          })
        : t('OUTSIDER_VOICE.CALL.INTERNAL', {
            extension: party.monitor.extension,
          });
    }
    if ((party.number || '').length <= 4) {
      return t('OUTSIDER_VOICE.CALL.INTERNAL', { extension: party.number });
    }
    if (party.lookup?.contact) return formatPhone(party.number);
    return t('OUTSIDER_VOICE.CALL.UNKNOWN');
  };

  const elapsed = party =>
    formatDuration((now.value.getTime() - party.answeredAt) / 1000);

  // situação de alguém da conferência: chamando, tempo na conversa ou como acabou
  const guestState = guest => {
    if (guest.state === 'ended') {
      return t(`OUTSIDER_VOICE.CALL.ENDED.${guest.endReason || 'DONE'}`);
    }
    if (guest.state === 'active') return elapsed(guest);
    return t('OUTSIDER_VOICE.CALL.DIALING');
  };

  const title = computed(() => nameOf(call.value));
  const subtitle = computed(() => detailOf(call.value));

  const people = computed(
    () =>
      (call.value?.others || []).filter(other => other.state === 'active')
        .length + 1
  );

  const stateLabel = computed(() => {
    if (!call.value) return '';
    const { state, endReason, held, transferTo } = call.value;
    if (state === 'ended') {
      return t(`OUTSIDER_VOICE.CALL.ENDED.${endReason}`, {
        extension: transferTo,
      });
    }
    if (state === 'active') {
      const time = elapsed(call.value);
      return held ? t('OUTSIDER_VOICE.CALL.ON_HOLD', { time }) : time;
    }
    return t(
      state === 'ringing'
        ? 'OUTSIDER_VOICE.CALL.INCOMING'
        : 'OUTSIDER_VOICE.CALL.DIALING'
    );
  });

  // na janela própria do telefone, abre na janela do Chatwoot que a abriu (ver PhoneDock.vue)
  const go = location => {
    if (isPopoutWindow() && window.opener && !window.opener.closed) {
      window.opener.postMessage(
        {
          type: 'outsider-phone-navigate',
          href: router.resolve(location).fullPath,
        },
        window.location.origin
      );
      window.opener.focus();
      return;
    }
    router.push(location);
  };

  const openDeal = (id = linkedDeal.value?.id || deal.value?.id) =>
    go({
      path: frontendURL(`accounts/${accountId.value}/crm/opportunities`),
      query: { negocio: id },
    });

  // cadastro completo do cliente (Contatos), aberto na tela do Chatwoot
  const openContact = (id = contact.value?.id) =>
    go(frontendURL(`accounts/${accountId.value}/contacts/${id}`));

  const openConversation = () =>
    go(
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
    deals,
    linkedDeal,
    ivr,
    monitor,
    title,
    subtitle,
    stateLabel,
    people,
    nameOf,
    detailOf,
    guestState,
    openDeal,
    openContact,
    openConversation,
  };
};
