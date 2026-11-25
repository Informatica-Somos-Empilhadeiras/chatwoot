<script setup>
// OUTSIDER: "Abrir conversa" do cliente do ERP num painel de detalhe. Um cliente do ERP pode estar ligado a vários
// contatos do chat (comprador, financeiro, gerente...): com um só, o botão abre a conversa dele; com vários, abre a lista
// para escolher (o da conversa mais recente primeiro). Sem nenhum, e com search (a busca de contatos da tela), "Ligar
// contato" procura um contato e liga ao cliente (Outsider::Erp::ContactLink, só no chat; o ERP não muda).
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { erpErrorMessage } from '../erpStore';

const props = defineProps({
  // [{ id, name, phone, email, conversation_id }] (Records::ContactFinder#for_client)
  contacts: { type: Array, default: () => [] },
  company: { type: String, default: '' },
  clientCode: { type: Number, default: 0 },
  clientName: { type: String, default: '' },
  label: { type: String, default: '' },
  // q => Promise<{ data: { contacts } }>; sem ela não oferece ligar contato
  search: { type: Function, default: null },
});

const emit = defineEmits(['linked']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const mode = ref('');
const found = ref([]);
const searching = ref(false);
const linking = ref(false);

const canLink = computed(() => Boolean(props.search && props.clientCode));

const target = contact => {
  const accountId = route.params.accountId;
  return frontendURL(
    contact.conversation_id
      ? `accounts/${accountId}/conversations/${contact.conversation_id}`
      : `accounts/${accountId}/contacts/${contact.id}`
  );
};

const go = contact => router.push(target(contact));

const single = computed(() =>
  props.contacts.length === 1 ? props.contacts[0] : null
);

const buttonLabel = computed(() => {
  if (!props.contacts.length) return t('OUTSIDER_ERP.RECORDS.LINK_CONTACT');
  if (single.value && !single.value.conversation_id)
    return t('OUTSIDER_ERP.RECORDS.OPEN_CONTACT');
  return props.label || t('OUTSIDER_ERP.RECORDS.OPEN_CHAT');
});

const contactLine = contact =>
  [contact.name, contact.phone || contact.email].filter(Boolean).join(' · ');

const chooseItems = computed(() => [
  ...props.contacts.map(contact => ({
    action: 'open',
    value: contact.id,
    label: contactLine(contact),
    icon: contact.conversation_id
      ? 'i-lucide-message-circle'
      : 'i-lucide-user-round',
    contact,
  })),
  ...(canLink.value
    ? [
        {
          action: 'search',
          value: 'search',
          label: t('OUTSIDER_ERP.RECORDS.LINK_ANOTHER'),
          icon: 'i-lucide-user-plus',
        },
      ]
    : []),
]);

const linked = new Set();
const searchItems = computed(() =>
  found.value
    .filter(contact => !props.contacts.some(item => item.id === contact.id))
    .map(contact => ({
      action: 'link',
      value: contact.id,
      label: [contact.name, contact.phone_number || contact.email]
        .filter(Boolean)
        .join(' · '),
      icon: 'i-lucide-link',
      contact,
    }))
);

const runSearch = debounce(async q => {
  if (!String(q || '').trim()) {
    found.value = [];
    searching.value = false;
    return;
  }
  try {
    const { data } = await props.search(q);
    found.value = data.contacts || [];
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    searching.value = false;
  }
}, 300);

const onSearch = q => {
  searching.value = true;
  runSearch(q);
};

const close = () => {
  mode.value = '';
  found.value = [];
};

const link = async contact => {
  if (linking.value || linked.has(contact.id)) return;
  linking.value = true;
  try {
    await ErpAPI.link({
      contact_id: contact.id,
      company: props.company,
      code: props.clientCode,
      name: props.clientName || undefined,
    });
    linked.add(contact.id);
    close();
    useAlert(t('OUTSIDER_ERP.RECORDS.LINKED', { name: contact.name }));
    emit('linked');
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    linking.value = false;
  }
};

const click = () => {
  if (mode.value) {
    close();
    return;
  }
  if (single.value && !canLink.value) {
    go(single.value);
    return;
  }
  mode.value = props.contacts.length ? 'choose' : 'search';
};

const onAction = item => {
  if (item.action === 'open') {
    close();
    go(item.contact);
  } else if (item.action === 'search') {
    mode.value = 'search';
  } else if (item.action === 'link') {
    link(item.contact);
  }
};
</script>

<template>
  <div
    v-if="contacts.length || canLink"
    v-on-click-outside="close"
    class="relative"
  >
    <Button
      size="sm"
      variant="faded"
      color="slate"
      :icon="contacts.length ? 'i-lucide-message-circle' : 'i-lucide-user-plus'"
      :label="
        contacts.length > 1
          ? `${buttonLabel} (${contacts.length})`
          : buttonLabel
      "
      :is-loading="linking"
      data-erp-client-chat
      @click="click"
    />
    <DropdownMenu
      v-if="mode === 'choose'"
      :menu-items="chooseItems"
      class="top-full mt-1 ltr:left-0 rtl:right-0 min-w-64 max-w-80 z-30"
      @action="onAction"
    />
    <DropdownMenu
      v-else-if="mode === 'search'"
      :menu-items="searchItems"
      show-search
      disable-local-filtering
      :is-searching="searching"
      :search-placeholder="t('OUTSIDER_ERP.RECORDS.LINK_SEARCH')"
      empty-state-message="OUTSIDER_ERP.RECORDS.LINK_EMPTY"
      class="top-full mt-1 ltr:left-0 rtl:right-0 min-w-72 max-w-80 max-h-80 z-30"
      @search="onSearch"
      @action="onAction"
    />
  </div>
</template>
