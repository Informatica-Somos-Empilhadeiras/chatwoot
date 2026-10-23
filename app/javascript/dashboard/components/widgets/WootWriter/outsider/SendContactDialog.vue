<script setup>
// OUTSIDER: janela "Enviar contato", aberta pelo menu do clipe (ComposerAttachMenu.vue), só nas caixas da Evolution.
// Abre a escolha de contatos (busca no Chatwoot pelo nome ou telefone, ou nome e número digitados)
// e envia como cartão de contato do WhatsApp (ver app/services/outsider/contact_card_sender.rb).
// A mensagem aparece na conversa quando a Evolution confirma o envio.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ContactAPI from 'dashboard/api/contacts';
import ContactCardsAPI from 'dashboard/api/outsider/contactCards';

const props = defineProps({
  conversationId: { type: Number, default: null },
});

const MAX_CONTACTS = 10;

const { t } = useI18n();

const dialogRef = ref(null);
const query = ref('');
const results = ref([]);
const isSearching = ref(false);
const selected = ref([]);
const manualName = ref('');
const manualPhone = ref('');
const isSending = ref(false);
let searchController = null;


const digits = value => String(value || '').replace(/\D/g, '');
const keyOf = item => `${item.name}|${digits(item.phone)}`;
const isSelected = item =>
  selected.value.some(row => keyOf(row) === keyOf(item));
const isFull = computed(() => selected.value.length >= MAX_CONTACTS);

// grupos e contatos sem telefone não viram cartão
const toItem = contact => ({
  id: contact.id,
  name: contact.name,
  phone: contact.phone_number || '',
  email: contact.email || '',
  company: contact.additional_attributes?.company_name || '',
  thumbnail: contact.thumbnail || '',
  isGroup: String(contact.identifier || '').endsWith('@g.us'),
});

const search = useDebounceFn(async term => {
  searchController?.abort();
  if (term.trim().length < 2) {
    results.value = [];
    isSearching.value = false;
    return;
  }
  searchController = new AbortController();
  isSearching.value = true;
  try {
    const { data } = await ContactAPI.search(term.trim(), 1, 'name', '', {
      signal: searchController.signal,
    });
    results.value = (data.payload || [])
      .map(toItem)
      .filter(item => !item.isGroup);
    isSearching.value = false;
  } catch (error) {
    if (error?.name !== 'CanceledError') isSearching.value = false;
  }
}, 300);

watch(query, term => {
  isSearching.value = term.trim().length >= 2;
  search(term);
});

const toggle = item => {
  if (!item.phone) return;
  if (isSelected(item)) {
    selected.value = selected.value.filter(row => keyOf(row) !== keyOf(item));
  } else if (!isFull.value) {
    selected.value = [...selected.value, item];
  }
};

const manualValid = computed(
  () =>
    manualName.value.trim() &&
    digits(manualPhone.value).length >= 10 &&
    digits(manualPhone.value).length <= 15
);

const addManual = () => {
  if (!manualValid.value || isFull.value) return;
  const item = {
    id: null,
    name: manualName.value.trim(),
    phone: manualPhone.value.trim(),
    email: '',
    company: '',
    thumbnail: '',
  };
  if (!isSelected(item)) selected.value = [...selected.value, item];
  manualName.value = '';
  manualPhone.value = '';
};

const open = () => {
  query.value = '';
  results.value = [];
  selected.value = [];
  manualName.value = '';
  manualPhone.value = '';
  dialogRef.value?.open();
};

const errorMessage = error => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_WHATSAPP.SEND_CONTACT.ERRORS.${String(code || '').toUpperCase()}`;
  if (code && t(key) !== key) return t(key);
  return (
    error?.response?.data?.message ||
    t('OUTSIDER_WHATSAPP.SEND_CONTACT.ERRORS.DEFAULT')
  );
};

const send = async () => {
  if (!selected.value.length || isSending.value) return;
  isSending.value = true;
  try {
    await ContactCardsAPI.send(
      props.conversationId,
      selected.value.map(({ name, phone, email, company }) => ({
        name,
        phone,
        email: email || undefined,
        company: company || undefined,
      }))
    );
    dialogRef.value?.close();
    useAlert(
      selected.value.length > 1
        ? t('OUTSIDER_WHATSAPP.SEND_CONTACT.SENT_MANY')
        : t('OUTSIDER_WHATSAPP.SEND_CONTACT.SENT_ONE')
    );
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSending.value = false;
  }
};

defineExpose({ open });

const fieldClass =
  'w-full !mb-0 px-3 py-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP.SEND_CONTACT.TITLE')"
    :description="t('OUTSIDER_WHATSAPP.SEND_CONTACT.DESCRIPTION')"
    :confirm-button-label="
      selected.length
        ? t('OUTSIDER_WHATSAPP.SEND_CONTACT.SEND_COUNT', {
            count: selected.length,
          })
        : t('OUTSIDER_WHATSAPP.SEND_CONTACT.SEND')
    "
    :disable-confirm-button="!selected.length"
    :is-loading="isSending"
    width="md"
    @confirm="send"
  >
    <div class="flex flex-col gap-4" data-send-contact-dialog>
      <div v-if="selected.length" class="flex flex-wrap gap-1.5">
        <span
          v-for="item in selected"
          :key="keyOf(item)"
          class="inline-flex items-center gap-1 py-1 pl-2.5 pr-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
        >
          {{ item.name }}
          <button
            type="button"
            class="grid rounded-full size-4 place-content-center hover:bg-n-alpha-3"
            :aria-label="t('OUTSIDER_WHATSAPP.SEND_CONTACT.REMOVE')"
            @click="toggle(item)"
          >
            <Icon icon="i-lucide-x" class="size-3" />
          </button>
        </span>
      </div>

      <div class="relative">
        <Icon
          icon="i-lucide-search"
          class="absolute -translate-y-1/2 pointer-events-none size-4 left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="search"
          :class="fieldClass"
          class="!pl-9"
          :placeholder="t('OUTSIDER_WHATSAPP.SEND_CONTACT.SEARCH')"
          @keydown.enter.prevent
        />
      </div>

      <div class="flex flex-col overflow-y-auto max-h-64 -mx-1">
        <p
          v-if="isSearching"
          class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.SEARCHING') }}
        </p>
        <p
          v-else-if="query.trim().length < 2"
          class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.HINT') }}
        </p>
        <p
          v-else-if="!results.length"
          class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.NO_RESULTS') }}
        </p>
        <template v-else>
          <button
            v-for="item in results"
            :key="item.id"
            type="button"
            class="flex items-center gap-3 px-2 py-2 text-left rounded-lg hover:bg-n-alpha-1 disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="!item.phone || (isFull && !isSelected(item))"
            data-contact-result
            @click="toggle(item)"
          >
            <Avatar
              :name="item.name"
              :src="item.thumbnail"
              :size="32"
              rounded-full
            />
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-sm truncate text-n-slate-12">{{
                item.name
              }}</span>
              <span class="text-xs truncate text-n-slate-11">
                {{ item.phone || t('OUTSIDER_WHATSAPP.SEND_CONTACT.NO_PHONE') }}
              </span>
            </span>
            <Icon
              :icon="
                isSelected(item) ? 'i-lucide-circle-check' : 'i-lucide-circle'
              "
              class="size-5 shrink-0"
              :class="isSelected(item) ? 'text-n-teal-10' : 'text-n-slate-8'"
            />
          </button>
        </template>
      </div>

      <div class="flex flex-col gap-2 pt-3 border-t border-n-weak">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.MANUAL') }}
        </span>
        <div class="flex flex-wrap items-center gap-2">
          <input
            v-model="manualName"
            type="text"
            maxlength="100"
            :class="fieldClass"
            class="flex-1 min-w-[8rem]"
            :placeholder="t('OUTSIDER_WHATSAPP.SEND_CONTACT.NAME')"
            @keydown.enter.prevent="addManual"
          />
          <input
            v-model="manualPhone"
            type="tel"
            maxlength="25"
            :class="fieldClass"
            class="flex-1 min-w-[8rem]"
            :placeholder="t('OUTSIDER_WHATSAPP.SEND_CONTACT.PHONE')"
            @keydown.enter.prevent="addManual"
          />
          <NextButton
            type="button"
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-plus"
            :label="t('OUTSIDER_WHATSAPP.SEND_CONTACT.ADD')"
            :disabled="!manualValid || isFull"
            @click="addManual"
          />
        </div>
        <span v-if="isFull" class="text-xs text-n-amber-11">
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.LIMIT', { max: MAX_CONTACTS }) }}
        </span>
      </div>
    </div>
  </Dialog>
</template>
