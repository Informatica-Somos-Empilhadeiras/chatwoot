<script setup>
// OUTSIDER (técnicos): a ligação em tela cheia no Meu telefone, no jeito da ligação do WhatsApp: fundo verde escuro,
// foto grande pulsando enquanto toca, Recusar e Atender. Em ligação: tempo, Mudo, Teclado (tons para a URA do
// cliente), Espera, Transferir e Incluir (conferência com um colega) e Encerrar. Botões grandes para usar com luva.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  addToConference,
  answer,
  clearEndedCall,
  hangup,
  inConference,
  phone,
  sendDigit,
  toggleHold,
  toggleMute,
  transfer,
} from '../phone';
import { useCallInfo } from '../useCallInfo';
import { formatPhone } from '../format';
import { colleagueOf, loadTeam, presenceOf, techState } from './techStore';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

const { t } = useI18n();
const { call, title, stateLabel } = useCallInfo();

const panel = ref(null); // keypad | transfer | include
const tones = ref('');

const internal = computed(() => (call.value?.number || '').length <= 4);
const colleague = computed(() =>
  internal.value ? colleagueOf(call.value?.number) : null
);
const name = computed(() => colleague.value?.name || title.value);
const photo = computed(
  () =>
    colleague.value?.thumbnail || call.value?.lookup?.contact?.thumbnail || ''
);
// número sem nome: o símbolo do telefone no lugar de "(1" como iniciais
const onlyNumber = computed(() => !/\p{L}/u.test(name.value || ''));
const detail = computed(() => {
  if (!call.value) return '';
  if (internal.value) {
    return [
      t('OUTSIDER_VOICE.TECH.EXTENSION', { extension: call.value.number }),
      colleague.value?.branch,
    ]
      .filter(Boolean)
      .join(' · ');
  }
  return call.value.lookup?.contact
    ? `${formatPhone(call.value.number)} · ${t('OUTSIDER_VOICE.TECH.CUSTOMER')}`
    : formatPhone(call.value.number);
});

const ringing = computed(
  () => call.value?.state === 'ringing' && call.value.direction === 'inbound'
);
const active = computed(() => call.value?.state === 'active');
const ended = computed(() => call.value?.state === 'ended');
const top = computed(() => {
  if (ringing.value) return t('OUTSIDER_VOICE.TECH.CALL_SCREEN.INCOMING');
  if (active.value) return t('OUTSIDER_VOICE.TECH.CALL_SCREEN.ACTIVE');
  if (ended.value) return t('OUTSIDER_VOICE.TECH.CALL_SCREEN.ENDED');
  return t('OUTSIDER_VOICE.TECH.CALL_SCREEN.OUTGOING');
});

const canHold = computed(() => active.value && !inConference());
const canTransfer = computed(() => active.value && !inConference());
const colleagues = computed(() =>
  techState.team.filter(
    person =>
      person.id !== phone.userId &&
      person.extension !== call.value?.number &&
      !['in_call', 'offline'].includes(presenceOf(person))
  )
);

watch(
  () => call.value?.state,
  state => {
    if (state !== 'active') panel.value = null;
    if (state === 'active') tones.value = '';
  }
);

const openPicker = kind => {
  loadTeam();
  panel.value = panel.value === kind ? null : kind;
};

const press = digit => {
  tones.value = `${tones.value}${digit}`.slice(-24);
  sendDigit(digit);
};

const pick = person => {
  if (panel.value === 'transfer') transfer(person.extension);
  else {
    const error = addToConference(person.extension);
    if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
  }
  panel.value = null;
};
</script>

<template>
  <div
    class="outsider-tech-call-screen"
    :class="{ 'is-ringing': ringing }"
    data-testid="outsider-tech-call-screen"
  >
    <p class="flex items-center gap-1.5 mt-6 text-sm opacity-80">
      <span
        v-if="active"
        class="inline-block rounded-full size-2 bg-[#90eb54]"
      />
      <span v-else class="i-lucide-phone size-3.5" />
      {{ top }}
    </p>
    <p
      class="px-6 mt-8 text-3xl font-semibold text-center"
      data-testid="outsider-tech-call-name"
    >
      {{ name }}
    </p>
    <p class="px-6 mt-1.5 text-base text-center opacity-75 tabular-nums">
      <template v-if="active || ended">{{ stateLabel }}</template>
      <template v-else>{{ detail }}</template>
    </p>
    <p v-if="active && detail" class="mt-0.5 text-sm opacity-60">
      {{ detail }}
    </p>

    <div
      class="outsider-tech-call-screen__photo"
      :class="{ 'is-small': active && panel }"
    >
      <Avatar
        :name="name || '?'"
        :src="photo"
        :icon-name="onlyNumber && !photo ? 'i-lucide-phone' : null"
        :size="active ? 112 : 160"
        rounded-full
      />
    </div>

    <div v-if="active && panel === 'keypad'" class="w-full px-10 mt-auto">
      <p class="h-7 mb-2 text-xl text-center tracking-widest tabular-nums">
        {{ tones }}
      </p>
      <div class="grid grid-cols-3 gap-x-6 gap-y-3 justify-items-center">
        <button
          v-for="digit in KEYS"
          :key="digit"
          type="button"
          class="outsider-tech-call-screen__key"
          @click="press(digit)"
        >
          {{ digit }}
        </button>
      </div>
    </div>

    <div
      v-else-if="active && (panel === 'transfer' || panel === 'include')"
      class="w-full px-4 mt-auto overflow-y-auto max-h-[45%]"
      data-testid="outsider-tech-call-picker"
    >
      <p class="px-2 mb-2 text-sm font-semibold opacity-80">
        {{
          t(
            panel === 'transfer'
              ? 'OUTSIDER_VOICE.TECH.CALL_SCREEN.TRANSFER_TO'
              : 'OUTSIDER_VOICE.TECH.CALL_SCREEN.INCLUDE_WHO'
          )
        }}
      </p>
      <p v-if="!colleagues.length" class="px-2 text-sm opacity-70">
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.NOBODY_FREE') }}
      </p>
      <button
        v-for="person in colleagues"
        :key="person.id"
        type="button"
        class="flex items-center w-full gap-3 px-2 py-2 text-left rounded-xl hover:bg-white/10"
        @click="pick(person)"
      >
        <Avatar
          :name="person.name"
          :src="person.thumbnail || ''"
          :size="36"
          rounded-full
        />
        <span class="flex-1 min-w-0">
          <span class="block font-semibold truncate">{{ person.name }}</span>
          <span class="block text-xs truncate opacity-70">
            {{ person.extension }}
            <template v-if="person.branch"> · {{ person.branch }}</template>
          </span>
        </span>
      </button>
    </div>

    <div
      v-else-if="active"
      class="grid grid-cols-3 px-8 mt-auto gap-x-4 gap-y-6"
    >
      <button
        type="button"
        class="outsider-tech-call-screen__tool"
        :class="{ 'is-on': call.muted }"
        data-testid="outsider-tech-mute"
        @click="toggleMute"
      >
        <span class="outsider-tech-call-screen__tool-icon">
          <span class="i-lucide-mic-off size-6" />
        </span>
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.MUTE') }}
      </button>
      <button
        type="button"
        class="outsider-tech-call-screen__tool"
        @click="panel = 'keypad'"
      >
        <span class="outsider-tech-call-screen__tool-icon">
          <span class="i-lucide-grid-3x3 size-6" />
        </span>
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.KEYPAD') }}
      </button>
      <button
        type="button"
        class="outsider-tech-call-screen__tool"
        :class="{ 'is-on': call.held }"
        :disabled="!canHold"
        @click="toggleHold"
      >
        <span class="outsider-tech-call-screen__tool-icon">
          <span class="i-lucide-pause size-6" />
        </span>
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.HOLD') }}
      </button>
      <button
        type="button"
        class="outsider-tech-call-screen__tool"
        :disabled="!canTransfer"
        @click="openPicker('transfer')"
      >
        <span class="outsider-tech-call-screen__tool-icon">
          <span class="i-lucide-arrow-right-left size-6" />
        </span>
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.TRANSFER') }}
      </button>
      <button
        type="button"
        class="outsider-tech-call-screen__tool"
        @click="openPicker('include')"
      >
        <span class="outsider-tech-call-screen__tool-icon">
          <span class="i-lucide-user-plus size-6" />
        </span>
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.INCLUDE') }}
      </button>
    </div>

    <div class="flex justify-around w-full px-8 mt-auto mb-10 pt-6">
      <template v-if="ringing">
        <button
          type="button"
          class="outsider-tech-call-screen__big"
          data-testid="outsider-tech-decline"
          @click="hangup"
        >
          <span class="outsider-tech-call-screen__circle is-red">
            <span class="i-lucide-phone-off size-8" />
          </span>
          {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.DECLINE') }}
        </button>
        <button
          type="button"
          class="outsider-tech-call-screen__big"
          data-testid="outsider-tech-answer"
          @click="answer"
        >
          <span class="outsider-tech-call-screen__circle is-green is-pulse">
            <span class="i-lucide-phone size-8" />
          </span>
          {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.ANSWER') }}
        </button>
      </template>
      <button
        v-else-if="ended"
        type="button"
        class="outsider-tech-call-screen__big"
        @click="clearEndedCall"
      >
        <span class="outsider-tech-call-screen__circle is-ghost">
          <span class="i-lucide-x size-8" />
        </span>
        {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.CLOSE') }}
      </button>
      <template v-else>
        <button
          v-if="panel"
          type="button"
          class="outsider-tech-call-screen__big"
          @click="panel = null"
        >
          <span class="outsider-tech-call-screen__circle is-ghost">
            <span class="i-lucide-chevron-down size-8" />
          </span>
          {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.BACK') }}
        </button>
        <button
          type="button"
          class="outsider-tech-call-screen__big"
          data-testid="outsider-tech-hangup"
          @click="hangup"
        >
          <span class="outsider-tech-call-screen__circle is-red">
            <span class="i-lucide-phone-off size-8" />
          </span>
          {{ t('OUTSIDER_VOICE.TECH.CALL_SCREEN.HANG_UP') }}
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.outsider-tech-call-screen {
  position: absolute;
  inset: 0;
  z-index: 30;
  display: flex;
  flex-direction: column;
  align-items: center;
  overflow: hidden;
  color: #fff;
  background: radial-gradient(
    ellipse at 50% 30%,
    #1f4d3a 0%,
    #0e2a20 45%,
    #07150f 100%
  );
  padding-bottom: env(safe-area-inset-bottom, 0);
}

.outsider-tech-call-screen__photo {
  position: relative;
  margin-top: 2.5rem;
  display: flex;
  align-items: center;
  justify-content: center;
}

.outsider-tech-call-screen__photo.is-small {
  margin-top: 1rem;
  transform: scale(0.7);
}

.is-ringing .outsider-tech-call-screen__photo::before,
.is-ringing .outsider-tech-call-screen__photo::after {
  content: '';
  position: absolute;
  inset: -1.1rem;
  border-radius: 50%;
  border: 2px solid rgba(144, 235, 84, 0.3);
  animation: outsider-tech-ring 1.8s ease-out infinite;
}

.is-ringing .outsider-tech-call-screen__photo::after {
  animation-delay: 0.9s;
}

@keyframes outsider-tech-ring {
  from {
    transform: scale(0.95);
    opacity: 1;
  }

  to {
    transform: scale(1.35);
    opacity: 0;
  }
}

.outsider-tech-call-screen__tool {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.8rem;
}

.outsider-tech-call-screen__tool:disabled {
  opacity: 0.4;
}

.outsider-tech-call-screen__tool-icon {
  width: 3.9rem;
  height: 3.9rem;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.12);
}

.outsider-tech-call-screen__tool.is-on .outsider-tech-call-screen__tool-icon {
  background: #fff;
  color: #0e2a20;
}

.outsider-tech-call-screen__key {
  width: 4rem;
  height: 4rem;
  border-radius: 50%;
  font-size: 1.6rem;
  background: rgba(255, 255, 255, 0.12);
}

.outsider-tech-call-screen__big {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.875rem;
}

.outsider-tech-call-screen__circle {
  width: 4.6rem;
  height: 4.6rem;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.outsider-tech-call-screen__circle.is-red {
  background: #e53935;
}

.outsider-tech-call-screen__circle.is-green {
  background: #1fb85b;
}

.outsider-tech-call-screen__circle.is-ghost {
  background: rgba(255, 255, 255, 0.14);
}

.outsider-tech-call-screen__circle.is-pulse {
  animation: outsider-tech-pulse 1.2s ease-in-out infinite;
}

@keyframes outsider-tech-pulse {
  50% {
    transform: scale(1.08);
    box-shadow: 0 0 0 10px rgba(31, 184, 91, 0.2);
  }
}
</style>
