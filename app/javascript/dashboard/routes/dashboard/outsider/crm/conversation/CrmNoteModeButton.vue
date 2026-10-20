<script setup>
// OUTSIDER: botão "Nota CRM" ao lado de Responder / Nota privada (ReplyTopPanel.vue). Aparece
// quando o contato da conversa tem negócio que a pessoa enxerga e troca a caixa de resposta pelo
// editor de nota interna do CRM (CrmReplyArea.vue).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { crmState, summaryKey } from '../crmStore';

const { t } = useI18n();
const chat = useMapGetter('getSelectedChat');

const summary = computed(
  () =>
    crmState.summaries[summaryKey(chat.value?.meta?.sender?.id, chat.value?.id)]
);

const visible = computed(
  () =>
    crmState.access.enabled &&
    !summary.value?.group &&
    !!summary.value?.opportunities?.some(item => item.status !== 'forwarded')
);
</script>

<template>
  <button
    v-if="visible"
    type="button"
    class="inline-flex items-center gap-1 h-8 px-2.5 text-sm rounded-full text-n-violet-11 bg-n-violet-2 hover:bg-n-violet-3 outline outline-1 -outline-offset-1 outline-n-violet-5"
    :title="t('OUTSIDER_CRM.NOTE.BUTTON_HINT')"
    @click="crmState.noteMode = true"
  >
    <Icon icon="i-lucide-sticky-note" class="size-3.5" />
    {{ t('OUTSIDER_CRM.NOTE.BUTTON') }}
  </button>
</template>
