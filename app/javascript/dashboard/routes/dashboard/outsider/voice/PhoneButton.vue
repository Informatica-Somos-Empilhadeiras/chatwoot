<script setup>
// OUTSIDER: o telefone no rodapé do menu lateral (Entrega 22). O ponto mostra se está pronto para ligar;
// clicando abre o teclado para discar um número ou ramal, o teste de áudio e, se for o caso, como
// reconectar ou trazer o telefone para esta aba. Só aparece para quem tem ramal ligado.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PhoneKeypad from './PhoneKeypad.vue';
import { phone, dial, restartPhone, useThisTab, sendDigit } from './phone';

const DOT = {
  ready: 'bg-n-teal-9',
  connecting: 'bg-n-amber-9',
  offline: 'bg-n-ruby-9',
  failed: 'bg-n-ruby-9',
  other_tab: 'bg-n-slate-8',
};

const { t } = useI18n();
const isOpen = ref(false);
const number = ref('');

const inCall = computed(() =>
  ['dialing', 'active', 'ringing'].includes(phone.call?.state)
);
const hint = computed(() =>
  ['offline', 'failed', 'other_tab'].includes(phone.status)
    ? t(`OUTSIDER_VOICE.PHONE.HINTS.${phone.status}`)
    : ''
);

const call = target => {
  const error = dial(target);
  if (error) {
    useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
    return;
  }
  number.value = '';
  isOpen.value = false;
};

const press = digit => {
  if (phone.call?.state === 'active') sendDigit(digit);
  else number.value += digit;
};
</script>

<template>
  <div
    v-if="phone.status !== 'off'"
    v-on-click-outside="() => (isOpen = false)"
    class="relative flex-shrink-0"
  >
    <button
      type="button"
      class="relative flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
      :class="{ 'bg-n-alpha-1 text-n-slate-12': isOpen }"
      :title="`${t('OUTSIDER_VOICE.PHONE.TITLE')} · ${t(`OUTSIDER_VOICE.PHONE.STATUS.${phone.status}`)}`"
      data-testid="outsider-phone-button"
      @click="isOpen = !isOpen"
    >
      <Icon icon="i-lucide-phone" class="size-4" />
      <span
        class="absolute rounded-full size-2 bottom-1 ltr:right-1 rtl:left-1 outline outline-2 outline-n-background"
        :class="DOT[phone.status]"
      />
    </button>

    <div
      v-if="isOpen"
      class="absolute z-50 flex flex-col gap-3 p-3 mb-2 border shadow-lg bottom-full ltr:left-0 rtl:right-0 w-72 rounded-xl border-n-weak bg-n-alpha-3 backdrop-blur-[100px]"
    >
      <div class="flex items-center justify-between gap-2">
        <div class="min-w-0">
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PHONE.TITLE') }}
          </div>
          <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
            <span class="rounded-full size-2" :class="DOT[phone.status]" />
            {{ t(`OUTSIDER_VOICE.PHONE.STATUS.${phone.status}`) }}
          </div>
        </div>
        <span
          class="px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
        >
          {{
            t('OUTSIDER_VOICE.PHONE.EXTENSION', { extension: phone.extension })
          }}
        </span>
      </div>

      <template v-if="hint">
        <p class="mb-0 text-xs text-n-slate-11">{{ hint }}</p>
        <Button
          v-if="phone.status === 'other_tab'"
          sm
          :label="t('OUTSIDER_VOICE.PHONE.USE_HERE')"
          icon="i-lucide-monitor-smartphone"
          @click="useThisTab"
        />
        <Button
          v-else
          sm
          slate
          :label="t('OUTSIDER_VOICE.PHONE.RECONNECT')"
          icon="i-lucide-refresh-cw"
          @click="restartPhone"
        />
      </template>

      <template v-else-if="phone.status === 'ready'">
        <form
          v-if="!inCall"
          class="flex items-center gap-1.5"
          @submit.prevent="call(number)"
        >
          <input
            v-model="number"
            type="tel"
            autocomplete="off"
            :placeholder="t('OUTSIDER_VOICE.PHONE.NUMBER_PLACEHOLDER')"
            class="flex-1 min-w-0 !mb-0 h-9 px-3 text-base rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
            data-testid="outsider-phone-number"
          />
          <Button
            v-if="number"
            type="button"
            sm
            ghost
            slate
            icon="i-lucide-delete"
            :title="t('OUTSIDER_VOICE.PHONE.CLEAR')"
            @click="number = number.slice(0, -1)"
          />
        </form>
        <PhoneKeypad @press="press" />
        <Button
          v-if="!inCall"
          sm
          teal
          icon="i-lucide-phone"
          :label="t('OUTSIDER_VOICE.PHONE.CALL')"
          :disabled="!number"
          data-testid="outsider-phone-call"
          @click="call(number)"
        />
        <button
          v-if="!inCall"
          type="button"
          class="flex items-start gap-2 p-2 text-left rounded-lg hover:bg-n-alpha-2"
          data-testid="outsider-phone-echo"
          @click="call(phone.echoExtension)"
        >
          <Icon
            icon="i-lucide-headphones"
            class="flex-shrink-0 mt-0.5 size-4 text-n-slate-11"
          />
          <span class="flex flex-col">
            <span class="text-sm text-n-slate-12">
              {{ t('OUTSIDER_VOICE.PHONE.ECHO_TEST') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_VOICE.PHONE.ECHO_HINT') }}
            </span>
          </span>
        </button>
      </template>
    </div>
  </div>
</template>
