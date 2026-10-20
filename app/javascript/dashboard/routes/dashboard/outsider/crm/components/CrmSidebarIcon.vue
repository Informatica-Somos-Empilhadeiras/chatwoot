<script setup>
// OUTSIDER: ícone do CRM no menu lateral. Mostra uma bolinha vermelha enquanto houver negócio
// recebido por encaminhamento que a pessoa ainda não abriu, e é quem liga o aviso (ForwardNotice),
// já que o menu está em todas as páginas. Se o ícone aparecer em mais de um lugar ao mesmo tempo,
// só o primeiro mostra a janela. Também liga o lembrete de tarefas e a contagem de tarefas do menu.
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ForwardNotice from './ForwardNotice.vue';
import { crmState, startReceivedWatch, startTaskReminders } from '../crmStore';

const { t } = useI18n();
const isOwner = ref(false);
let token = null;

const unread = computed(() => crmState.received.length);

onMounted(() => {
  if (!window.outsiderCrmNoticeOwner) {
    token = Symbol('notice');
    window.outsiderCrmNoticeOwner = token;
    isOwner.value = true;
  }
  startReceivedWatch();
  startTaskReminders(t);
});

onBeforeUnmount(() => {
  if (token && window.outsiderCrmNoticeOwner === token) {
    window.outsiderCrmNoticeOwner = null;
  }
});
</script>

<template>
  <span class="relative inline-flex size-4 shrink-0">
    <span class="i-lucide-handshake size-4" />
    <span
      v-if="unread"
      v-tooltip.right="t('OUTSIDER_CRM.NOTICE.DOT', unread)"
      class="absolute rounded-full -top-1 -right-1 size-2.5 bg-n-ruby-9 ring-2 ring-n-solid-2"
    />
    <ForwardNotice v-if="isOwner" />
  </span>
</template>
