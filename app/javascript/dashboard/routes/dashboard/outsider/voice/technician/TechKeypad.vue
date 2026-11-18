<script setup>
// OUTSIDER (técnicos): aba Teclado do Meu telefone. Digitando, mostra quem é (colega pelo ramal ou contato do
// Chatwoot pelo número). "Sair com" mostra o número da empresa que o cliente vê e deixa trocar neste aparelho
// (sem "Ligar para fora" no perfil, só ramais). Teclas grandes para usar com luva; o teclado do computador também.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener, useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import { phone, dial, setLine, currentLine } from '../phone';
import { formatPhone } from '../format';
import TechHeader from './TechHeader.vue';
import TechPushNudge from './TechPushNudge.vue';
import { colleagueOf } from './techStore';

const KEYS = [
  ['1', ''],
  ['2', 'ABC'],
  ['3', 'DEF'],
  ['4', 'GHI'],
  ['5', 'JKL'],
  ['6', 'MNO'],
  ['7', 'PQRS'],
  ['8', 'TUV'],
  ['9', 'WXYZ'],
  ['*', ''],
  ['0', '+'],
  ['#', ''],
];
const MAX_DIGITS = 16;

const { t } = useI18n();
const number = ref('');
const contactName = ref('');
const choosing = ref(false);

const internal = computed(() => number.value.length <= 4);
const shown = computed(() =>
  internal.value ? number.value : formatPhone(number.value)
);
const who = computed(() => {
  if (!number.value) return '';
  if (internal.value) {
    const colleague = colleagueOf(number.value);
    return colleague
      ? [colleague.name, colleague.branch].filter(Boolean).join(' · ')
      : '';
  }
  return contactName.value;
});

const line = computed(() => currentLine());
const lineLabel = item =>
  [formatPhone(item.number), item.label || item.state]
    .filter(Boolean)
    .join(' · ');

const lookupNumber = useDebounceFn(async value => {
  if (value !== number.value || value.length < 8) return;
  try {
    const { data } = await VoiceAPI.lookup(value);
    if (value === number.value) contactName.value = data?.contact?.name || '';
  } catch {
    if (value === number.value) contactName.value = '';
  }
}, 400);

watch(number, value => {
  contactName.value = '';
  if (value.length >= 8) lookupNumber(value);
});

const press = digit => {
  if (number.value.length >= MAX_DIGITS) return;
  number.value += digit;
};
const erase = () => {
  number.value = number.value.slice(0, -1);
};
const clear = () => {
  number.value = '';
};

const call = () => {
  if (!number.value) return;
  const error = dial(number.value);
  if (error) {
    useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
    return;
  }
  number.value = '';
};

const choose = value => {
  setLine(value);
  choosing.value = false;
};

// teclado do computador (e colar um número)
useEventListener(window, 'keydown', event => {
  if (phone.call && phone.call.state !== 'ended') return;
  const target = event.target;
  if (target?.closest?.('input, textarea, [contenteditable="true"]')) return;
  if (/^[0-9*#]$/.test(event.key)) press(event.key);
  else if (event.key === 'Backspace') erase();
  else if (event.key === 'Enter') call();
  else return;
  event.preventDefault();
});
useEventListener(window, 'paste', event => {
  if (event.target?.closest?.('input, textarea, [contenteditable="true"]'))
    return;
  const text = event.clipboardData?.getData('text') || '';
  const digits = text.replace(/[^\d*#]/g, '').slice(0, MAX_DIGITS);
  if (digits) number.value = digits;
});
</script>

<template>
  <div class="flex flex-col min-h-full">
    <TechHeader />
    <TechPushNudge />

    <button
      v-if="phone.outbound && line"
      type="button"
      class="flex items-center justify-between gap-3 px-3 py-2 mx-4 mt-3 text-sm border border-solid rounded-xl border-n-weak text-n-slate-11"
      data-testid="outsider-tech-line"
      @click="choosing = true"
    >
      <span class="truncate">
        {{ t('OUTSIDER_VOICE.TECH.LINE') }}
        <b class="font-semibold text-n-slate-12">{{ lineLabel(line) }}</b>
      </span>
      <span class="font-semibold text-n-blue-11 shrink-0">
        {{ t('OUTSIDER_VOICE.TECH.LINE_CHANGE') }}
      </span>
    </button>
    <p
      v-else-if="!phone.outbound"
      class="px-3 py-2 mx-4 mt-3 text-sm text-center rounded-xl bg-n-alpha-2 text-n-slate-11"
    >
      {{ t('OUTSIDER_VOICE.TECH.ONLY_EXTENSIONS') }}
    </p>

    <div class="flex flex-col items-center justify-center flex-1 py-4">
      <div class="flex items-center justify-center w-full gap-2 px-6">
        <span
          class="flex-1 text-4xl font-light tracking-wide text-center truncate tabular-nums text-n-slate-12 min-h-12"
          data-testid="outsider-tech-number"
        >
          {{ shown }}
        </span>
      </div>
      <p class="h-5 mt-1 text-sm text-n-slate-11">{{ who }}</p>

      <div class="grid grid-cols-3 mt-4 outsider-tech-pad gap-x-8 gap-y-4">
        <button
          v-for="[digit, letters] in KEYS"
          :key="digit"
          type="button"
          class="outsider-tech-key"
          :data-testid="`outsider-tech-key-${digit}`"
          @click="press(digit)"
        >
          <b>{{ digit }}</b>
          <span>{{ letters }}</span>
        </button>
      </div>

      <div class="grid items-center grid-cols-3 mt-5 gap-x-8">
        <span />
        <button
          type="button"
          class="outsider-tech-call"
          :disabled="!number"
          :aria-label="t('OUTSIDER_VOICE.TECH.CALL')"
          data-testid="outsider-tech-call"
          @click="call"
        >
          <span class="text-white i-lucide-phone size-8" />
        </button>
        <button
          v-if="number"
          type="button"
          class="flex items-center justify-center size-16 text-n-slate-11"
          :aria-label="t('OUTSIDER_VOICE.TECH.ERASE')"
          @click="erase"
          @contextmenu.prevent="clear"
          @dblclick="clear"
        >
          <span class="i-lucide-delete size-7" />
        </button>
      </div>
    </div>

    <div
      v-if="choosing"
      class="absolute inset-0 z-20 flex items-end bg-black/40"
      @click.self="choosing = false"
    >
      <div
        class="w-full p-4 pb-6 rounded-t-3xl bg-n-solid-1"
        data-testid="outsider-tech-lines"
      >
        <p class="mb-1 text-base font-semibold text-n-slate-12">
          {{ t('OUTSIDER_VOICE.TECH.LINE_TITLE') }}
        </p>
        <p class="mb-3 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.TECH.LINE_HINT') }}
        </p>
        <button
          type="button"
          class="outsider-tech-option"
          :class="{ 'is-on': !phone.chosenLine }"
          @click="choose('')"
        >
          <span class="flex-1 text-left">
            {{ t('OUTSIDER_VOICE.TECH.LINE_AUTO') }}
            <span v-if="phone.line" class="block text-xs text-n-slate-11">
              {{ lineLabel(phone.line) }}
            </span>
          </span>
          <span v-if="!phone.chosenLine" class="i-lucide-check size-5" />
        </button>
        <button
          v-for="item in phone.lines"
          :key="item.number"
          type="button"
          class="outsider-tech-option"
          :class="{ 'is-on': phone.chosenLine === item.number }"
          @click="choose(item.number)"
        >
          <span class="flex-1 text-left">{{ lineLabel(item) }}</span>
          <span
            v-if="phone.chosenLine === item.number"
            class="i-lucide-check size-5"
          />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.outsider-tech-key {
  width: 4.75rem;
  height: 4.75rem;
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
  touch-action: manipulation;
  transition: background 0.12s;
}

.outsider-tech-key:active {
  background: rgb(var(--slate-5));
}

.outsider-tech-key b {
  font-size: 1.75rem;
  font-weight: 500;
  line-height: 1;
}

.outsider-tech-key span {
  height: 0.75rem;
  margin-top: 0.2rem;
  font-size: 0.625rem;
  letter-spacing: 0.1em;
  color: rgb(var(--slate-10));
}

.outsider-tech-call {
  width: 4.75rem;
  height: 4.75rem;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #1fb85b;
  box-shadow: 0 6px 18px rgba(31, 184, 91, 0.4);
  touch-action: manipulation;
}

.outsider-tech-call:disabled {
  opacity: 0.55;
  box-shadow: none;
}

.outsider-tech-option {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem;
  border-radius: 0.75rem;
  font-size: 0.9rem;
  color: rgb(var(--slate-12));
}

.outsider-tech-option.is-on {
  background: rgb(var(--slate-3));
  font-weight: 600;
}

@media (max-height: 640px) {
  .outsider-tech-key,
  .outsider-tech-call {
    width: 4rem;
    height: 4rem;
  }
}
</style>
