<script setup>
// OUTSIDER: botão "Ligar" no topo da conversa, ao lado de Resolver, para o agente achar o telefone
// sem precisar abrir o painel do contato. Para não gerar ligação por clique sem querer, abre uma
// confirmação simples logo abaixo ("Ligar para Maria Aparecida?", o número, Cancelar / Ligar): Enter
// liga, Esc ou clicar fora cancela. A ligação sai pelo telefone do CRM, igual ao CallButton.vue.
// Só aparece para quem tem ramal ligado, quando o contato tem número e não é um grupo do WhatsApp.
import { computed, nextTick, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { onClickOutside, useEventListener } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { isGroupConversation } from 'dashboard/helper/outsider/groupConversations';
import { phone, dial } from './phone';
import { formatPhone } from './format';

const props = defineProps({
  chat: { type: Object, default: null },
  inbox: { type: Object, default: null },
});

const POPOVER_WIDTH = 268;

const { t } = useI18n();
const store = useStore();

// o cadastro do contato (pode ter o número atualizado) ou, sem ele carregado, o da conversa
const contact = computed(() => {
  const sender = props.chat?.meta?.sender;
  const stored = sender?.id
    ? store.getters['contacts/getContact'](sender.id)
    : null;
  return stored?.id ? stored : sender || null;
});
const number = computed(() => contact.value?.phone_number || '');
// caixa de voz do próprio Chatwoot já tem o botão de ligação dela
const isVoiceInbox = computed(
  () => props.inbox?.channel_type === 'Channel::Voice'
);
const visible = computed(
  () =>
    phone.status !== 'off' &&
    !!number.value &&
    !isVoiceInbox.value &&
    !isGroupConversation(props.chat)
);
// "Maria Aparecida" em vez do nome inteiro
const shortName = computed(() =>
  (contact.value?.name || formatPhone(number.value))
    .split(/\s+/)
    .slice(0, 2)
    .join(' ')
);

const open = ref(false);
const buttonRef = ref(null);
const popoverRef = ref(null);
const confirmRef = ref(null);
const position = ref({ top: 0, left: 0, arrow: 0 });

const place = () => {
  const rect = buttonRef.value?.getBoundingClientRect();
  if (!rect) return;
  const center = rect.left + rect.width / 2;
  const left = Math.min(
    Math.max(8, center - POPOVER_WIDTH + 44),
    window.innerWidth - POPOVER_WIDTH - 8
  );
  position.value = { top: rect.bottom + 10, left, arrow: center - left };
};

const close = () => {
  open.value = false;
};
const toggle = async () => {
  if (open.value) {
    close();
    return;
  }
  place();
  open.value = true;
  await nextTick();
  confirmRef.value?.focus();
};

const call = () => {
  close();
  const error = dial(number.value);
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
};

onClickOutside(popoverRef, close, { ignore: [buttonRef] });
useEventListener(document, 'keydown', event => {
  if (open.value && event.key === 'Escape') close();
});
useEventListener(window, 'resize', () => open.value && place());
// trocou de conversa: a pergunta era para o contato anterior
watch(() => props.chat?.id, close);
</script>

<template>
  <button
    v-if="visible"
    ref="buttonRef"
    type="button"
    class="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg border text-sm font-semibold whitespace-nowrap transition-colors bg-[#E9F8DE] text-[#00663B] border-[#BFE8A3] hover:bg-[#DDF4CC] dark:bg-[rgb(144_235_84_/_0.1)] dark:text-[#90EB54] dark:border-[rgb(144_235_84_/_0.35)] dark:hover:bg-[rgb(144_235_84_/_0.16)]"
    :class="{
      '!bg-[#D9F4C6] !border-[#9FDC77] dark:!bg-[rgb(144_235_84_/_0.18)]': open,
    }"
    :title="t('OUTSIDER_VOICE.HEADER_CALL.TITLE')"
    :aria-expanded="open"
    data-testid="outsider-header-call"
    @click="toggle"
  >
    <span class="i-lucide-phone size-4 shrink-0" />
    <span class="hidden sm:inline">{{
      t('OUTSIDER_VOICE.HEADER_CALL.BUTTON')
    }}</span>
  </button>

  <Teleport to="body">
    <div
      v-if="visible && open"
      ref="popoverRef"
      role="dialog"
      :aria-label="
        t('OUTSIDER_VOICE.HEADER_CALL.QUESTION', { name: shortName })
      "
      class="fixed z-[120] p-3.5 rounded-[14px] border border-n-weak bg-white dark:bg-n-solid-3 shadow-[0_16px_36px_-12px_rgb(0_0_0_/_0.28)] text-n-slate-12"
      :style="{
        top: `${position.top}px`,
        left: `${position.left}px`,
        width: `${POPOVER_WIDTH}px`,
      }"
      data-testid="outsider-header-call-confirm"
    >
      <span
        class="absolute -top-[7px] size-3 rotate-45 border-l border-t border-n-weak bg-white dark:bg-n-solid-3"
        :style="{ left: `${position.arrow - 6}px` }"
      />
      <p class="m-0 text-sm font-semibold leading-5">
        {{ t('OUTSIDER_VOICE.HEADER_CALL.QUESTION', { name: shortName }) }}
      </p>
      <p
        class="flex items-center gap-1.5 m-0 mt-0.5 text-[13px] text-n-slate-11"
      >
        <span class="i-lucide-phone size-3.5 shrink-0" />
        {{ formatPhone(number) }}
      </p>
      <div class="flex justify-end gap-2 mt-3">
        <button
          type="button"
          class="h-8 px-3 rounded-[9px] text-[13px] font-semibold bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
          @click="close"
        >
          {{ t('OUTSIDER_VOICE.HEADER_CALL.CANCEL') }}
        </button>
        <button
          ref="confirmRef"
          type="button"
          class="inline-flex items-center gap-1.5 h-8 px-3 rounded-[9px] text-[13px] font-semibold bg-[#00663B] text-white hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#90EB54]"
          data-testid="outsider-header-call-go"
          @click="call"
        >
          <span class="i-lucide-phone size-3.5 shrink-0" />
          {{ t('OUTSIDER_VOICE.HEADER_CALL.CONFIRM') }}
        </button>
      </div>
    </div>
  </Teleport>
</template>
