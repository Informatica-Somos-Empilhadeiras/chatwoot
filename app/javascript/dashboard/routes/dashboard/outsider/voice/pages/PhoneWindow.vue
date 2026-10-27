<script setup>
// OUTSIDER: o telefone na janela própria (Entrega 24), aberta pelo botão do topo do telefone. Só o telefone,
// sem o menu do Chatwoot, para deixar ao lado ou em outro monitor. A linha vem para esta janela (as abas do
// Chatwoot viram controle remoto dela); fechar a janela devolve a linha para uma aba aberta.
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import PhonePanel from '../PhonePanel.vue';
import { usePhoneLifecycle } from '../usePhoneLifecycle';
import { phone } from '../phone';

const { t } = useI18n();

usePhoneLifecycle({ popout: true });

onMounted(() => {
  document.title = t('OUTSIDER_VOICE.PHONE.TITLE');
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-solid-2">
    <PhonePanel v-if="phone.status !== 'off'" windowed />
    <p v-else class="p-6 m-0 text-sm text-center text-n-slate-11">
      {{ t('OUTSIDER_VOICE.PHONE.WINDOW_OFF') }}
    </p>
  </div>
</template>
