<script setup>
// OUTSIDER: o telefone em destaque no topo do menu, logo abaixo do nome da pessoa, para o agente achar
// sozinho. Mostra se está pronto e o ramal; "Ligar" abre o teclado do telefone (PhonePanel) ou a janela
// própria dele. Recolhido, vira o botão redondo verde. Só aparece para quem tem ramal ligado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  phone,
  panel,
  setPanelOpen,
  showPopout,
  askNotifications,
} from '../../voice/phone';

defineProps({
  collapsed: { type: Boolean, default: false },
});

const { t } = useI18n();

const inCall = computed(() => !!phone.call && phone.call.state !== 'ended');
const state = computed(() => (inCall.value ? 'in_call' : phone.status));
const problem = computed(() => ['offline', 'failed'].includes(phone.status));
const dotClass = computed(() =>
  state.value === 'offline' ? 'is-phone-offline' : `is-${state.value}`
);

const subtitle = computed(() => {
  const status = t(`OUTSIDER_NAV.PHONE.STATUS.${state.value}`);
  return phone.extension
    ? `${status} · ${t('OUTSIDER_NAV.PHONE.EXTENSION', { extension: phone.extension })}`
    : status;
});
const title = computed(() => `${t('OUTSIDER_NAV.PHONE.TITLE')} · ${subtitle.value}`);

const reveal = open => {
  askNotifications();
  if (phone.popout && !phone.holder) showPopout();
  else setPanelOpen(open);
};
const toggle = () => reveal(!panel.open);
const openKeypad = () => reveal(true);
</script>

<template>
  <template v-if="phone.status !== 'off'">
    <button
      v-if="collapsed"
      v-tooltip.right="title"
      type="button"
      class="onav-rph"
      :aria-label="title"
      data-testid="outsider-phone-button"
      @click="toggle"
    >
      <span class="i-lucide-phone size-5" />
      <span class="onav-status" :class="dotClass" />
    </button>

    <div
      v-else
      class="onav-phone"
      :class="{ 'is-problem': problem }"
      data-testid="outsider-phone-card"
    >
      <button
        type="button"
        class="onav-phone-main"
        :title="title"
        :aria-expanded="panel.open"
        @click="toggle"
      >
        <span class="onav-phone-ico">
          <span class="i-lucide-phone size-4" />
          <span class="onav-status" :class="dotClass" />
        </span>
        <span class="onav-phone-txt">
          <span class="onav-phone-t">{{ t('OUTSIDER_NAV.PHONE.TITLE') }}</span>
          <span class="onav-phone-s">{{ subtitle }}</span>
        </span>
      </button>
      <button
        type="button"
        class="onav-phone-btn"
        data-testid="outsider-phone-button"
        @click="openKeypad"
      >
        <span class="i-lucide-phone-outgoing size-3.5" />
        {{ inCall ? t('OUTSIDER_NAV.PHONE.OPEN') : t('OUTSIDER_NAV.PHONE.CALL') }}
      </button>
    </div>
  </template>
</template>
