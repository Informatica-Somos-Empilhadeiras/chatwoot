<script setup>
// OUTSIDER: na conversa, mostra acima da mensagem o status que o contato respondeu ou
// curtiu, como no WhatsApp. Encaixado em components-next/message/bubbles/Base.vue.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useMessageContext } from 'dashboard/components-next/message/provider.js';
import StatusThumbnail from './StatusThumbnail.vue';
import { fetchRepliedStatus, typeLabel } from '../helpers';

const { t } = useI18n();
const { contentAttributes, inboxId } = useMessageContext();

const status = ref(null);

const statusId = computed(
  () => contentAttributes.value?.outsiderReplyToExternalId
);

const preview = computed(
  () => status.value.text || typeLabel(t, status.value.type)
);

watch(
  statusId,
  id => {
    status.value = null;
    if (!id) return;
    fetchRepliedStatus(inboxId.value, id).then(result => {
      if (id === statusId.value) status.value = result;
    });
  },
  { immediate: true }
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="status"
    class="flex items-center gap-2 p-2 -mx-1 mb-2 overflow-hidden rounded-lg bg-n-alpha-black1 ltr:border-l-4 rtl:border-r-4 border-n-teal-9"
  >
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <span class="flex items-center gap-1 text-xs font-medium text-n-teal-11">
        <Icon icon="i-lucide-circle-dashed" class="size-3.5 shrink-0" />
        {{ t('OUTSIDER_WHATSAPP_STATUS.REPLY_QUOTE.LABEL') }}
      </span>
      <span class="line-clamp-2 break-words text-n-slate-11">
        {{ preview }}
      </span>
    </div>
    <StatusThumbnail
      v-if="status.type !== 'text'"
      :status="status"
      :inbox-id="inboxId"
      class="rounded-md size-10 shrink-0"
    />
  </div>
</template>
