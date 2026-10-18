<script setup>
// OUTSIDER: botão verde de gravar áudio, dentro da caixa de texto, preso ao
// canto de baixo (acompanha a caixa quando ela cresce), como no WhatsApp.
import NextButton from 'dashboard/components-next/button/Button.vue';
</script>

<template>
  <NextButton
    v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
    icon="i-ph-microphone-fill"
    class="!absolute ltr:right-1 rtl:left-1 bottom-1 z-10 !w-9 !h-9 !rounded-full !bg-[#00a884] !text-white hover:enabled:!bg-[#008f6f] shadow-sm [&>span]:size-5"
  />
</template>
