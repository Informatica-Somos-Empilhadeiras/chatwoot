<script setup>
// OUTSIDER: resultado da busca que está com outro agente. Mostra o contato e o agente
// em destaque, mas não abre a conversa: o agente pede a transferência para quem está com ela
// (transferRequests.js), que aceita ou recusa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { timeAgo } from 'dashboard/helper/outsider/timeAgo';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  transferState,
  pendingRequestFor,
  requestTransfer,
  cancelTransfer,
} from 'dashboard/routes/dashboard/outsider/transfer/transferRequests';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t, locale } = useI18n();
const getInbox = useMapGetter('inboxes/getInbox');

const contact = computed(() => props.conversation.meta.sender);
const assignee = computed(() => props.conversation.meta.assignee);
const inboxName = computed(
  () => getInbox.value(props.conversation.inbox_id)?.name
);
const details = computed(() =>
  [
    contact.value.phone_number &&
      (parsePhoneNumberFromString(
        contact.value.phone_number
      )?.formatInternational() ??
        contact.value.phone_number),
    inboxName.value,
    props.conversation.status !== 'open' &&
      t(`CHAT_LIST.OUTSIDER_SEARCH.STATUS.${props.conversation.status}`),
  ]
    .filter(Boolean)
    .join(' · ')
);

// pedido meu esperando resposta (a lista de pedidos vale mais que a resposta da busca)
const pendingRequest = computed(() => {
  const fromState = pendingRequestFor(props.conversation.id);
  if (fromState || transferState.loaded) return fromState;
  const fromSearch = props.conversation.outsider_transfer_request;
  return fromSearch?.status === 'pending' ? fromSearch : null;
});
const isBusy = computed(
  () =>
    transferState.busy[`conversation-${props.conversation.id}`] ||
    (pendingRequest.value && transferState.busy[pendingRequest.value.id])
);

const ERRORS = ['not_assigned_to_other', 'not_found'];

const askTransfer = async () => {
  try {
    await requestTransfer(props.conversation.id);
    useAlert(
      t('OUTSIDER_TOOLS.TRANSFER.REQUEST_SENT', { name: assignee.value.name })
    );
  } catch (error) {
    const code = error?.response?.data?.error;
    useAlert(
      ERRORS.includes(code)
        ? t(`OUTSIDER_TOOLS.TRANSFER.ERRORS.${code}`)
        : t('OUTSIDER_TOOLS.TRANSFER.ERRORS.generic')
    );
  }
};

const cancelRequest = async () => {
  try {
    await cancelTransfer(pendingRequest.value.id);
  } catch (error) {
    useAlert(t('OUTSIDER_TOOLS.TRANSFER.ERRORS.generic'));
  }
};
</script>

<template>
  <div
    class="flex items-start gap-3 p-2.5 border rounded-lg select-none border-n-weak bg-n-alpha-1"
    :title="t('CHAT_LIST.OUTSIDER_SEARCH.LOCKED_HINT', { name: assignee.name })"
  >
    <Avatar
      :name="contact.name || ''"
      :src="contact.thumbnail"
      :size="36"
      rounded-full
    />
    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ contact.name }}
        </span>
        <span class="text-xs shrink-0 text-n-slate-10">
          {{ timeAgo(conversation.timestamp, locale) }}
        </span>
      </div>
      <span v-if="details" class="text-xs truncate text-n-slate-11">
        {{ details }}
      </span>
      <span
        class="inline-flex items-center self-start max-w-full gap-1.5 py-0.5 ltr:pl-0.5 ltr:pr-2 rtl:pr-0.5 rtl:pl-2 text-xs font-medium rounded-full bg-n-amber-3 text-n-amber-11"
      >
        <Avatar
          :name="assignee.name"
          :src="assignee.thumbnail"
          :size="16"
          rounded-full
        />
        <span class="truncate">
          {{
            t('CHAT_LIST.OUTSIDER_SEARCH.WITH_AGENT', { name: assignee.name })
          }}
        </span>
      </span>
      <div class="flex flex-wrap items-center gap-2 mt-1">
        <template v-if="pendingRequest">
          <span
            class="inline-flex items-center gap-1 text-xs font-medium text-n-teal-11"
          >
            <Icon icon="i-lucide-clock" class="size-3.5" />
            {{ t('OUTSIDER_TOOLS.TRANSFER.WAITING', { name: assignee.name }) }}
          </span>
          <Button
            :label="t('OUTSIDER_TOOLS.TRANSFER.CANCEL')"
            xs
            ghost
            slate
            :is-loading="!!isBusy"
            @click="cancelRequest"
          />
        </template>
        <Button
          v-else
          :label="t('OUTSIDER_TOOLS.TRANSFER.ASK')"
          icon="i-lucide-arrow-right-left"
          xs
          faded
          :is-loading="!!isBusy"
          @click="askTransfer"
        />
      </div>
    </div>
    <Icon icon="i-lucide-lock" class="size-4 shrink-0 text-n-slate-9" />
  </div>
</template>
