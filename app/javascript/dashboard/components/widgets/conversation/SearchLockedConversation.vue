<script setup>
// OUTSIDER: resultado da busca que está com outro agente. Mostra o contato e o agente
// em destaque, mas não abre a conversa: o agente pede para quem está com ela atribuir.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import { useMapGetter } from 'dashboard/composables/store';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
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
</script>

<template>
  <div
    class="flex items-center gap-3 p-2.5 border rounded-lg cursor-not-allowed select-none border-n-weak bg-n-alpha-1"
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
          {{ dynamicTime(conversation.timestamp) }}
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
    </div>
    <Icon icon="i-lucide-lock" class="size-4 shrink-0 text-n-slate-9" />
  </div>
</template>
