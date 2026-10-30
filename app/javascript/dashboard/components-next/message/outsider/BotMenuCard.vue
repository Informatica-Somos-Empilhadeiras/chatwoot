<script setup>
// OUTSIDER: o menu do bot na conversa, como o cliente vê no WhatsApp (lista ou botões), e a escolha do
// cliente na lista ou no botão só com a opção. Ver dashboard/helper/outsider/botMenu.js.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MessageMeta from '../MessageMeta.vue';
import { useMessageContext } from '../provider.js';
import BotMenuPreview from 'dashboard/routes/dashboard/outsider/bot/BotMenuPreview.vue';
import { botMenuOf, menuReplyOf } from 'dashboard/helper/outsider/botMenu';

const { content, contentAttributes } = useMessageContext();
const { t } = useI18n();

const menu = computed(() =>
  botMenuOf({ contentAttributes: contentAttributes.value })
);
const reply = computed(() => (menu.value ? null : menuReplyOf(content.value)));
</script>

<template>
  <div v-if="menu" class="flex flex-col items-end gap-1">
    <span class="flex items-center gap-1 text-[11px] text-n-slate-10">
      <Icon icon="i-lucide-bot" class="size-3.5" />
      {{ t('OUTSIDER_TOOLS.BOT.BUBBLE.MENU') }}
    </span>
    <BotMenuPreview v-bind="menu" />
    <MessageMeta class="justify-end text-n-slate-11" />
  </div>
  <div
    v-else-if="reply"
    class="flex flex-col gap-0.5 px-3 py-2 text-sm rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-weak max-w-xs text-n-slate-12"
  >
    <span class="flex items-center gap-1 text-[11px] text-n-slate-10">
      <Icon
        :icon="reply.kind === 'button' ? 'i-lucide-reply' : 'i-lucide-list'"
        class="size-3.5"
      />
      {{
        reply.kind === 'button'
          ? t('OUTSIDER_TOOLS.BOT.BUBBLE.BUTTON_REPLY')
          : t('OUTSIDER_TOOLS.BOT.BUBBLE.LIST_REPLY')
      }}
    </span>
    <span class="font-medium">{{ reply.title }}</span>
    <span v-if="reply.description" class="text-xs text-n-slate-11">
      {{ reply.description }}
    </span>
    <MessageMeta class="justify-end mt-1 text-n-slate-11" />
  </div>
</template>
