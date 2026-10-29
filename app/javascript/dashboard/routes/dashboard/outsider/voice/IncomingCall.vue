<script setup>
// OUTSIDER: ligação chegando (Entrega 25): janela grande no meio da tela, por cima de tudo, com quem liga, o
// negócio aberto e os botões grandes de atender e recusar. "Atender depois" esconde a janela e a ligação segue
// tocando no cartão pequeno (CallMini). Com a aba escondida, o aviso do navegador fica em usePhoneLifecycle.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useCallInfo } from './useCallInfo';
import { answer, hangup, askNotifications } from './phone';

const { t } = useI18n();
const { call, contact, deal, title, subtitle } = useCallInfo();

// id da ligação que a pessoa mandou para depois
const later = ref(null);

const visible = computed(
  () =>
    call.value?.state === 'ringing' &&
    call.value.direction === 'inbound' &&
    later.value !== call.value.id
);

watch(
  () => call.value?.id,
  () => {
    if (later.value && later.value !== call.value?.id) later.value = null;
  }
);

const pickUp = () => {
  askNotifications();
  answer();
};

const decline = () => hangup();

const answerLater = () => {
  later.value = call.value?.id ?? null;
};

useEventListener(window, 'keydown', event => {
  if (visible.value && event.key === 'Escape') answerLater();
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="visible"
      class="fixed inset-0 z-[9998] flex items-center justify-center p-4 bg-n-alpha-black1 backdrop-blur-[3px]"
      data-testid="outsider-incoming-call"
    >
      <div
        class="flex flex-col items-center w-full max-w-md gap-5 px-8 pt-10 pb-8 text-center shadow-2xl rounded-3xl bg-n-solid-2 outline outline-1 outline-n-container"
        role="alertdialog"
        :aria-label="t('OUTSIDER_VOICE.CALL.INCOMING')"
      >
        <span
          class="flex items-center gap-2 px-3 py-1 text-sm font-medium rounded-full bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-phone-incoming" class="size-4" />
          {{ t('OUTSIDER_VOICE.CALL.INCOMING') }}
        </span>

        <span class="relative flex items-center justify-center size-28">
          <span
            class="absolute inset-0 rounded-full bg-n-teal-9/30 animate-ping"
          />
          <span
            class="absolute rounded-full -inset-2 outline outline-2 outline-n-teal-9/40"
          />
          <Avatar
            :name="title || '?'"
            :src="contact?.thumbnail || ''"
            :size="112"
            rounded-full
          />
        </span>

        <span class="flex flex-col gap-1 min-w-0 max-w-full">
          <span
            class="text-2xl font-semibold truncate text-n-slate-12"
            data-testid="outsider-incoming-name"
          >
            {{ title }}
          </span>
          <span class="text-base text-n-slate-11">{{ subtitle }}</span>
        </span>

        <span
          v-if="deal"
          class="flex items-center max-w-full gap-2 px-3 py-2 text-sm rounded-xl bg-n-alpha-2 text-n-slate-12"
        >
          <Icon
            icon="i-lucide-kanban"
            class="size-4 shrink-0 text-n-slate-11"
          />
          <span class="truncate">
            {{
              t('OUTSIDER_VOICE.CALL.DEAL', {
                title: deal.title,
                stage: deal.stage,
              })
            }}
          </span>
        </span>

        <div class="grid w-full grid-cols-2 gap-4 pt-2">
          <button
            type="button"
            class="flex flex-col items-center justify-center gap-1.5 h-24 text-base font-medium text-white rounded-2xl bg-n-ruby-9 hover:bg-n-ruby-10"
            data-testid="outsider-incoming-reject"
            @click="decline"
          >
            <Icon icon="i-lucide-phone-off" class="size-7" />
            {{ t('OUTSIDER_VOICE.CALL.REJECT') }}
          </button>
          <button
            type="button"
            class="flex flex-col items-center justify-center gap-1.5 h-24 text-base font-medium text-white rounded-2xl bg-n-teal-9 hover:bg-n-teal-10"
            data-testid="outsider-incoming-answer"
            @click="pickUp"
          >
            <Icon icon="i-lucide-phone" class="size-7 animate-bounce" />
            {{ t('OUTSIDER_VOICE.CALL.ANSWER') }}
          </button>
        </div>

        <button
          type="button"
          class="text-sm text-n-slate-11 hover:text-n-slate-12 hover:underline"
          data-testid="outsider-incoming-later"
          @click="answerLater"
        >
          {{ t('OUTSIDER_VOICE.CALL.ANSWER_LATER') }}
        </button>
      </div>
    </div>
  </Teleport>
</template>
