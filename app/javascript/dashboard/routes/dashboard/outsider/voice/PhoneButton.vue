<script setup>
// OUTSIDER: o telefone no rodapé do menu lateral (Entrega 22). O ponto mostra se está pronto para ligar;
// clicando, abre ou minimiza o telefone fixo no canto da tela (PhonePanel, Entrega 23). Só aparece para
// quem tem ramal ligado. Com o telefone na janela própria (Entrega 24), mostra a janela.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  phone,
  panel,
  setPanelOpen,
  showPopout,
  askNotifications,
} from './phone';

const DOT = {
  ready: 'bg-n-teal-9',
  connecting: 'bg-n-amber-9',
  offline: 'bg-n-ruby-9',
  failed: 'bg-n-ruby-9',
  other_tab: 'bg-n-slate-8',
};

const { t } = useI18n();

const toggle = () => {
  askNotifications();
  if (phone.popout && !phone.holder) showPopout();
  else setPanelOpen(!panel.open);
};
</script>

<template>
  <button
    v-if="phone.status !== 'off'"
    type="button"
    class="relative flex items-center justify-center flex-shrink-0 rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
    :class="{ 'bg-n-alpha-1 text-n-slate-12': panel.open }"
    :title="`${t('OUTSIDER_VOICE.PHONE.TITLE')} · ${t(`OUTSIDER_VOICE.PHONE.STATUS.${phone.status}`)}`"
    data-testid="outsider-phone-button"
    @click="toggle"
  >
    <Icon icon="i-lucide-phone" class="size-4" />
    <span
      class="absolute rounded-full size-2 bottom-1 ltr:right-1 rtl:left-1 outline outline-2 outline-n-background"
      :class="DOT[phone.status]"
    />
  </button>
</template>
