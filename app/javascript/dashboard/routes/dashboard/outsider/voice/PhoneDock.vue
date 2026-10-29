<script setup>
// OUTSIDER: o telefone na tela, em qualquer página (Entrega 23): aberto e solto na tela (PhonePanel) ou,
// minimizado, só o cartão da ligação (CallMini). O ciclo de vida do telefone fica em usePhoneLifecycle.
// Entrega 24: com o telefone na janela própria, os atalhos de lá (negócio, conversa) abrem aqui.
// Entrega 25: ligação chegando abre a janela grande de atender (IncomingCall).
import { useRouter } from 'vue-router';
import { useEventListener } from '@vueuse/core';
import PhonePanel from './PhonePanel.vue';
import CallMini from './CallMini.vue';
import IncomingCall from './IncomingCall.vue';
import { usePhoneLifecycle } from './usePhoneLifecycle';
import { panel, phone } from './phone';

const router = useRouter();

usePhoneLifecycle();

useEventListener(window, 'message', ({ origin, data }) => {
  if (origin !== window.location.origin) return;
  if (data?.type === 'outsider-phone-navigate' && data.href) {
    router.push(data.href);
  }
});
</script>

<template>
  <PhonePanel v-if="panel.open && phone.status !== 'off'" />
  <CallMini v-else-if="phone.call" />
  <IncomingCall v-if="phone.status !== 'off'" />
</template>
