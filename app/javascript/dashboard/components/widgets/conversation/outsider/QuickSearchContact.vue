<script setup>
// OUTSIDER: um contato achado pela busca que não está nas conversas encontradas (sem conversa, ou só em
// caixas que o agente não vê). "Conversar" abre a nova conversa do Chatwoot já com o contato;
// clicar no resto abre a página do contato.
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contact: { type: Object, required: true },
  highlighted: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const details = computed(() => {
  const { phone_number: phone, email } = props.contact;
  const formatted =
    phone &&
    (parsePhoneNumberFromString(phone)?.formatInternational() ?? phone);
  return [formatted, email].filter(Boolean).join(' · ');
});

const openContact = () => {
  router.push({
    name: 'contacts_edit',
    params: { accountId: accountId.value, contactId: props.contact.id },
  });
};

// a nova conversa usa as caixas pelas quais dá para falar com o contato
const loadInboxes = () => {
  store.dispatch('contacts/fetchContactableInbox', props.contact.id);
};

onMounted(() => {
  store.dispatch('contacts/setContact', props.contact);
});
</script>

<template>
  <div
    class="flex items-center w-full gap-3 px-3 py-2 rounded-lg cursor-pointer hover:bg-n-alpha-2"
    :class="{ 'ring-1 ring-n-brand bg-n-alpha-2': highlighted }"
    @click="openContact"
  >
    <Avatar
      :name="contact.name || ''"
      :src="contact.thumbnail"
      :size="32"
      rounded-full
    />
    <div class="flex flex-col flex-1 min-w-0">
      <span class="text-sm font-medium truncate text-n-slate-12">
        {{ contact.name || details }}
      </span>
      <span v-if="details" class="text-xs truncate text-n-slate-11">
        {{ details }}
      </span>
    </div>
    <div @click.stop>
      <ComposeConversation :contact-id="String(contact.id)" align="start">
        <template #trigger>
          <Button
            :label="t('OUTSIDER_TOOLS.SEARCH.START_CONVERSATION')"
            icon="i-ph-chat-circle-dots"
            xs
            faded
            @click="loadInboxes"
          />
        </template>
      </ComposeConversation>
    </div>
  </div>
</template>
