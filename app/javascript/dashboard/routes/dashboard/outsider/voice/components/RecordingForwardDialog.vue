<script setup>
// OUTSIDER: encaminhar a gravação de uma ligação para um contato por WhatsApp ou e-mail (Entrega 25; ver
// app/services/outsider/voice/recording_forward.rb). Como no envio de proposta (ProposalSendDialog), lista o
// contato da ligação e a busca acha qualquer contato da conta; sem telefone ou sem e-mail ele fica travado.
// A mensagem aponta para o mesmo arquivo da gravação: nada é copiado.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { errorMessage } from '../../crm/helpers';
import { formatPhone } from '../format';

const { t } = useI18n();

const CHANNELS = [
  { key: 'whatsapp', icon: 'i-lucide-message-circle' },
  { key: 'email', icon: 'i-lucide-mail' },
];

const isOpen = ref(false);
const isLoading = ref(false);
const isSending = ref(false);
const call = ref(null);
const options = ref(null);
const channel = ref('whatsapp');
const inboxId = ref('');
const contactId = ref(null);
const searchText = ref('');
const searchResults = ref(null);
const isSearching = ref(false);
const message = ref('');
const knownContacts = ref([]);

const visibleContacts = computed(() => {
  if (!searchResults.value) return options.value?.contacts || [];
  const selected = knownContacts.value.find(
    contact => contact.id === contactId.value
  );
  const list = [...searchResults.value];
  if (selected && !list.some(contact => contact.id === selected.id)) {
    list.unshift(selected);
  }
  return list;
});

const selectedContact = computed(() =>
  knownContacts.value.find(contact => contact.id === contactId.value)
);

const blockedReason = contact => contact.blocked?.[channel.value];

const inboxOptions = computed(() =>
  (options.value?.inboxes[channel.value] || []).map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);

const pickInbox = () => {
  const available = inboxOptions.value.map(option => option.value);
  const preferred =
    channel.value === 'whatsapp'
      ? selectedContact.value?.default_inbox_id
      : null;
  if (preferred && available.includes(preferred)) {
    inboxId.value = preferred;
  } else if (!available.includes(inboxId.value)) {
    inboxId.value = available[0] ?? '';
  }
};

const pickContact = contact => {
  if (!blockedReason(contact)) contactId.value = contact.id;
};

const ensureContact = () => {
  const current = selectedContact.value;
  if (current && !blockedReason(current)) return;
  const first = visibleContacts.value.find(contact => !blockedReason(contact));
  contactId.value = first?.id ?? null;
};

watch(channel, () => {
  ensureContact();
  pickInbox();
});

watch(contactId, () => {
  if (channel.value === 'whatsapp') pickInbox();
});

const remember = contacts => {
  const ids = new Set(knownContacts.value.map(contact => contact.id));
  knownContacts.value = [
    ...knownContacts.value,
    ...contacts.filter(contact => !ids.has(contact.id)),
  ];
};

let searchTimer = null;
watch(searchText, value => {
  clearTimeout(searchTimer);
  if (!value.trim()) {
    searchResults.value = null;
    return;
  }
  searchTimer = setTimeout(async () => {
    isSearching.value = true;
    try {
      const { data } = await VoiceAPI.getRecordingForwardOptions(
        call.value.id,
        { q: value.trim() }
      );
      remember(data.contacts);
      searchResults.value = data.contacts;
    } catch (error) {
      useAlert(errorMessage(t, error));
    } finally {
      isSearching.value = false;
    }
  }, 300);
});

const noInbox = computed(() => !isLoading.value && !inboxOptions.value.length);

const problem = computed(() => {
  if (noInbox.value) return t('OUTSIDER_CRM.PROPOSALS.SEND.ERRORS.NO_INBOX');
  if (!contactId.value) return t('OUTSIDER_CRM.PROPOSALS.SEND.ERRORS.CONTACT');
  return '';
});

const close = () => {
  if (!isSending.value) isOpen.value = false;
};

const open = async current => {
  call.value = current;
  options.value = null;
  searchText.value = '';
  searchResults.value = null;
  knownContacts.value = [];
  contactId.value = null;
  message.value = '';
  isOpen.value = true;
  isLoading.value = true;
  try {
    const { data } = await VoiceAPI.getRecordingForwardOptions(current.id);
    options.value = data;
    remember(data.contacts);
    channel.value =
      !data.inboxes.whatsapp.length && data.inboxes.email.length
        ? 'email'
        : 'whatsapp';
    ensureContact();
    pickInbox();
  } catch (error) {
    useAlert(errorMessage(t, error));
    isOpen.value = false;
  } finally {
    isLoading.value = false;
  }
};

const send = async () => {
  if (problem.value) {
    useAlert(problem.value);
    return;
  }
  isSending.value = true;
  try {
    await VoiceAPI.forwardRecording(call.value.id, {
      channel: channel.value,
      contact_id: contactId.value,
      inbox_id: inboxId.value,
      message: message.value,
    });
    useAlert(
      t('OUTSIDER_VOICE.RECORDINGS.FORWARD.DONE', {
        name: selectedContact.value?.name || '',
      })
    );
    isSending.value = false;
    isOpen.value = false;
  } catch (error) {
    useAlert(error?.response?.data?.message || errorMessage(t, error));
  } finally {
    isSending.value = false;
  }
};

const contactLine = contact =>
  [
    contact.company_name,
    channel.value === 'email' ? contact.email : contact.phone_number,
  ]
    .filter(Boolean)
    .join(' · ');

const onKeydown = event => {
  if (event.key === 'Escape') close();
};

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-n-alpha-black1 backdrop-blur-[2px]"
      tabindex="-1"
      data-testid="recording-forward-dialog"
      @keydown="onKeydown"
    >
      <div
        class="flex flex-col w-full max-w-2xl max-h-full overflow-hidden shadow-xl rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header
          class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
        >
          <span class="flex flex-col min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ t('OUTSIDER_VOICE.RECORDINGS.FORWARD.TITLE') }}
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{
                call?.contact_name || formatPhone(call?.customer_number || '')
              }}
            </span>
          </span>
          <Button
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('OUTSIDER_CRM.CANCEL')"
            @click="close"
          />
        </header>

        <div v-if="isLoading" class="flex justify-center p-8">
          <Spinner class="text-n-slate-10" />
        </div>
        <div
          v-else
          class="flex flex-col flex-1 min-h-0 gap-4 p-4 overflow-y-auto"
        >
          <div class="flex flex-wrap items-end gap-3">
            <div class="flex flex-col gap-1 text-xs">
              <span class="text-n-slate-11">
                {{ t('OUTSIDER_CRM.PROPOSALS.SEND.CHANNEL') }}
              </span>
              <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1">
                <button
                  v-for="option in CHANNELS"
                  :key="option.key"
                  type="button"
                  class="flex items-center gap-1.5 px-3 h-8 text-sm rounded-md"
                  :class="
                    channel === option.key
                      ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                      : 'text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="channel = option.key"
                >
                  <Icon :icon="option.icon" class="size-4" />
                  {{
                    t(`OUTSIDER_CRM.PROPOSALS.SEND.${option.key.toUpperCase()}`)
                  }}
                </button>
              </div>
            </div>
            <label
              v-if="inboxOptions.length"
              class="flex flex-col flex-1 gap-1 text-xs min-w-[12rem]"
            >
              <span class="text-n-slate-11">
                {{ t('OUTSIDER_CRM.PROPOSALS.SEND.INBOX') }}
              </span>
              <Select
                v-model="inboxId"
                :options="inboxOptions"
                class="!w-full [&>select]:w-full"
              />
            </label>
          </div>

          <p
            v-if="noInbox"
            class="flex items-start gap-2 px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
          >
            <Icon
              icon="i-lucide-triangle-alert"
              class="size-4 mt-0.5 shrink-0"
            />
            {{
              channel === 'email'
                ? t('OUTSIDER_CRM.PROPOSALS.SEND.NO_EMAIL_INBOX')
                : t('OUTSIDER_CRM.PROPOSALS.SEND.NO_WHATSAPP_INBOX')
            }}
          </p>

          <div class="flex flex-col gap-2">
            <div class="flex items-center justify-between gap-2">
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.PROPOSALS.SEND.TO') }}
              </span>
              <Spinner v-if="isSearching" :size="14" class="text-n-slate-10" />
            </div>
            <input
              v-model="searchText"
              type="search"
              :placeholder="t('OUTSIDER_CRM.PROPOSALS.SEND.SEARCH')"
              class="!mb-0 !text-sm rounded-lg"
              data-testid="recording-forward-search"
            />
            <div
              class="flex flex-col overflow-y-auto divide-y rounded-lg max-h-64 divide-n-weak outline outline-1 -outline-offset-1 outline-n-weak"
            >
              <p
                v-if="!visibleContacts.length"
                class="px-3 py-4 mb-0 text-sm text-center text-n-slate-11"
              >
                {{ t('OUTSIDER_VOICE.RECORDINGS.FORWARD.NO_CONTACTS') }}
              </p>
              <button
                v-for="contact in visibleContacts"
                :key="contact.id"
                type="button"
                class="flex items-center gap-3 px-3 py-2 text-left"
                :class="[
                  blockedReason(contact)
                    ? 'cursor-not-allowed opacity-60'
                    : 'hover:bg-n-alpha-1',
                  contact.id === contactId ? 'bg-n-alpha-2' : '',
                ]"
                :disabled="!!blockedReason(contact)"
                :aria-pressed="contact.id === contactId"
                data-testid="recording-forward-contact"
                @click="pickContact(contact)"
              >
                <span
                  class="flex items-center justify-center rounded-full size-4 shrink-0 outline outline-1"
                  :class="
                    contact.id === contactId
                      ? 'outline-n-brand bg-n-brand'
                      : 'outline-n-slate-7'
                  "
                >
                  <span
                    v-if="contact.id === contactId"
                    class="rounded-full size-1.5 bg-white"
                  />
                </span>
                <Avatar
                  :name="contact.name || '?'"
                  :src="contact.thumbnail || ''"
                  :size="28"
                  rounded-full
                />
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ contact.name }}
                  </span>
                  <span class="text-xs truncate text-n-slate-11">
                    {{ contactLine(contact) || '—' }}
                  </span>
                </span>
                <span
                  v-if="blockedReason(contact)"
                  class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-md whitespace-nowrap bg-n-alpha-2 text-n-slate-11"
                >
                  <Icon icon="i-lucide-lock" class="size-3" />
                  {{
                    t(
                      `OUTSIDER_CRM.PROPOSALS.SEND.BLOCKED.${blockedReason(contact).toUpperCase()}`
                    )
                  }}
                </span>
              </button>
            </div>
          </div>

          <label class="flex flex-col gap-1 text-xs">
            <span class="text-n-slate-11">
              {{ t('OUTSIDER_VOICE.RECORDINGS.FORWARD.MESSAGE') }}
            </span>
            <textarea
              v-model="message"
              rows="3"
              maxlength="4000"
              :placeholder="t('OUTSIDER_VOICE.RECORDINGS.FORWARD.PLACEHOLDER')"
              class="!mb-0 !text-sm rounded-lg"
            />
          </label>

          <p class="flex items-center gap-2 mb-0 text-xs text-n-slate-11">
            <Icon icon="i-lucide-paperclip" class="size-3.5 shrink-0" />
            {{ t('OUTSIDER_VOICE.RECORDINGS.FORWARD.ATTACHMENT') }}
          </p>
        </div>

        <footer
          class="flex flex-wrap items-center justify-end gap-2 px-4 py-3 border-t border-n-weak"
        >
          <span
            v-if="problem && !isLoading"
            class="flex-1 text-xs text-n-slate-11"
          >
            {{ problem }}
          </span>
          <Button
            size="sm"
            variant="faded"
            color="slate"
            :label="t('OUTSIDER_CRM.CANCEL')"
            :disabled="isSending"
            @click="close"
          />
          <Button
            size="sm"
            icon="i-lucide-send"
            :label="t('OUTSIDER_VOICE.RECORDINGS.FORWARD.SUBMIT')"
            :is-loading="isSending"
            :disabled="!!problem || isLoading"
            data-testid="recording-forward-submit"
            @click="send"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>
