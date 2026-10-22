<script setup>
// OUTSIDER: bolha de cartão de contato estilo WhatsApp (ver helper/outsider/contactCard.js).
// Um contato: foto, nome e telefone, com "Conversar" e "Salvar contato" (ou "Ver contato" quando
// o número já é um contato do Chatwoot) embaixo. Vários: uma linha por contato com os mesmos
// botões em ícone; a partir do 4º, "Ver todos".
// Conversar abre a conversa mais recente do contato nesta caixa; sem conversa, abre a ficha do
// contato (lá dá para começar uma). Salvar cria o contato com o nome e o número do cartão.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import BaseBubble from '../bubbles/Base.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import ContactAPI from 'dashboard/api/contacts';
import { useMessageContext } from '../provider.js';
import { contactCardsOf } from 'dashboard/helper/outsider/contactCard';
import {
  findContactByPhone,
  rememberContact,
} from 'dashboard/helper/outsider/contactLookup';

const VISIBLE = 3;

const { content, contentAttributes, inboxId } = useMessageContext();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const parsed = computed(() =>
  contactCardsOf({
    content: content.value,
    contentAttributes: contentAttributes.value,
  })
);
const cards = computed(() => parsed.value?.cards || []);
const header = computed(() => parsed.value?.header);
const isSingle = computed(() => cards.value.length === 1);
const showAll = ref(false);
const visibleCards = computed(() =>
  showAll.value ? cards.value : cards.value.slice(0, VISIBLE)
);

// contato do Chatwoot de cada número (para a foto e para saber se já está salvo)
const known = ref({});
const busy = ref(null);

const phoneOf = card => card.phones[0] || '';
const keyOf = card => `${card.name}|${phoneOf(card)}`;

watch(
  cards,
  list => {
    list.forEach(card => {
      if (!phoneOf(card)) return;
      findContactByPhone(phoneOf(card)).then(contact => {
        known.value = { ...known.value, [keyOf(card)]: contact };
      });
    });
  },
  { immediate: true }
);

const contactFor = card => known.value[keyOf(card)];

const createContact = async card => {
  const digits = phoneOf(card).replace(/\D/g, '');
  const { data } = await ContactAPI.create({
    name: card.name,
    phone_number: `+${digits}`,
    email: card.email || undefined,
  });
  const contact = data.payload?.contact || data.payload || data;
  rememberContact(contact);
  known.value = { ...known.value, [keyOf(card)]: contact };
  return contact;
};

const openContact = contact =>
  router.push({
    name: 'contacts_edit',
    params: { accountId: route.params.accountId, contactId: contact.id },
  });

const withBusy = async (card, action, work) => {
  if (busy.value) return;
  busy.value = `${keyOf(card)}|${action}`;
  try {
    await work();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('OUTSIDER_WHATSAPP.CONTACT_CARD.ERROR')
    );
  } finally {
    busy.value = null;
  }
};

const isBusy = (card, action) => busy.value === `${keyOf(card)}|${action}`;

const save = card =>
  withBusy(card, 'save', async () => {
    const contact = contactFor(card) || (await createContact(card));
    openContact(contact);
  });

const chat = card =>
  withBusy(card, 'chat', async () => {
    const contact = contactFor(card) || (await createContact(card));
    const { data } = await ContactAPI.getConversations(contact.id);
    const conversations = (data.payload || [])
      .filter(item => item.inbox_id === inboxId.value)
      .sort((a, b) => {
        const open = (b.status !== 'resolved') - (a.status !== 'resolved');
        return open || b.last_activity_at - a.last_activity_at;
      });
    if (!conversations.length) {
      openContact(contact);
      return;
    }
    router.push({
      name: 'inbox_conversation',
      params: {
        accountId: route.params.accountId,
        conversation_id: conversations[0].id,
      },
    });
  });

const saveLabel = card =>
  contactFor(card)
    ? t('OUTSIDER_WHATSAPP.CONTACT_CARD.VIEW')
    : t('OUTSIDER_WHATSAPP.CONTACT_CARD.SAVE');
</script>

<template>
  <BaseBubble class="pt-2 pb-2 w-72 max-w-full" data-bubble-name="contact-card">
    <p v-if="header" class="px-3 pb-1 mb-0 font-semibold">
      {{ `${header}:` }}
    </p>
    <div
      v-for="card in visibleCards"
      :key="keyOf(card)"
      class="flex items-center gap-3 px-3 py-2"
      :class="{ 'border-b border-n-alpha-2 last:border-b-0': !isSingle }"
    >
      <Avatar
        :name="card.name"
        :src="contactFor(card)?.thumbnail || ''"
        :size="isSingle ? 44 : 36"
        rounded-full
      />
      <div class="flex-1 min-w-0">
        <p class="mb-0 font-semibold truncate text-n-slate-12">
          {{ card.name }}
        </p>
        <p
          v-for="phone in card.phones"
          :key="phone"
          class="mb-0 text-xs tabular-nums text-n-slate-11"
        >
          {{ phone }}
        </p>
        <p v-if="card.company" class="mb-0 text-xs truncate text-n-slate-11">
          {{ card.company }}
        </p>
      </div>
      <div v-if="!isSingle" class="flex items-center gap-1 shrink-0">
        <button
          v-tooltip.top="t('OUTSIDER_WHATSAPP.CONTACT_CARD.CHAT')"
          type="button"
          class="grid rounded-full size-8 place-content-center text-n-teal-11 hover:bg-n-alpha-2"
          :disabled="!phoneOf(card)"
          @click="chat(card)"
        >
          <Icon
            :icon="
              isBusy(card, 'chat')
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-message-circle'
            "
            class="size-4"
          />
        </button>
        <button
          v-tooltip.top="saveLabel(card)"
          type="button"
          class="grid rounded-full size-8 place-content-center text-n-teal-11 hover:bg-n-alpha-2"
          :disabled="!phoneOf(card)"
          @click="save(card)"
        >
          <Icon
            :icon="
              isBusy(card, 'save')
                ? 'i-lucide-loader-circle animate-spin'
                : contactFor(card)
                  ? 'i-lucide-user-round'
                  : 'i-lucide-user-round-plus'
            "
            class="size-4"
          />
        </button>
      </div>
    </div>
    <button
      v-if="cards.length > VISIBLE"
      type="button"
      class="w-full px-3 py-1 text-xs font-medium text-left text-n-teal-11 hover:underline"
      @click="showAll = !showAll"
    >
      {{
        showAll
          ? t('OUTSIDER_WHATSAPP.CONTACT_CARD.SHOW_LESS')
          : t('OUTSIDER_WHATSAPP.CONTACT_CARD.SHOW_ALL', {
              count: cards.length,
            })
      }}
    </button>
    <div
      v-if="isSingle && phoneOf(cards[0])"
      class="grid grid-cols-2 mt-1 border-t divide-x border-n-alpha-2 divide-n-alpha-2"
    >
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 py-2 text-sm font-medium text-n-teal-11 hover:bg-n-alpha-1"
        @click="chat(cards[0])"
      >
        <Icon
          v-if="isBusy(cards[0], 'chat')"
          icon="i-lucide-loader-circle"
          class="animate-spin size-4"
        />
        {{ t('OUTSIDER_WHATSAPP.CONTACT_CARD.CHAT') }}
      </button>
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 py-2 text-sm font-medium text-n-teal-11 hover:bg-n-alpha-1"
        @click="save(cards[0])"
      >
        <Icon
          v-if="isBusy(cards[0], 'save')"
          icon="i-lucide-loader-circle"
          class="animate-spin size-4"
        />
        {{ saveLabel(cards[0]) }}
      </button>
    </div>
  </BaseBubble>
</template>
