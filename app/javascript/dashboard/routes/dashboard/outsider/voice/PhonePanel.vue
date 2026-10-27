<script setup>
// OUTSIDER: o telefone aberto (Entrega 23, refeito na 24). Solto na tela: arrasta pelo topo e fica onde a
// pessoa deixar; o botão do topo abre o telefone numa janela própria (windowed, ver PhoneWindow.vue), que
// pode ir para outro monitor. Sem ligação: teclado grande e a equipe. Na ligação: quem é, tempo, barras da
// voz e os botões grandes em grade (espera, mudo, incluir na conferência, transferir, teclado e gravar), com
// o Encerrar vermelho embaixo. Na conferência, a lista de quem está na conversa, com o botão de tirar.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PhoneKeypad from './PhoneKeypad.vue';
import TeamList from './TeamList.vue';
import AudioLevel from './AudioLevel.vue';
import CallAction from './CallAction.vue';
import { useCallInfo } from './useCallInfo';
import { useFloating } from './useFloating';
import {
  phone,
  MAX_GUESTS,
  setPanelOpen,
  dial,
  answer,
  hangup,
  toggleMute,
  toggleHold,
  toggleRecording,
  canRecord,
  transfer,
  addToConference,
  removeFromConference,
  inConference,
  sendDigit,
  callStreams,
  clearEndedCall,
  restartPhone,
  useThisTab,
  openPopout,
  showPopout,
} from './phone';

const props = defineProps({
  // na janela própria do telefone: ocupa a janela toda, sem arrastar nem minimizar
  windowed: { type: Boolean, default: false },
});

const DOT = {
  ready: 'bg-n-teal-9',
  connecting: 'bg-n-amber-9',
  offline: 'bg-n-ruby-9',
  failed: 'bg-n-ruby-9',
  other_tab: 'bg-n-slate-8',
};
const DTMF = /^[0-9*#]$/;

const { t } = useI18n();
const { accountId } = useAccount();
const {
  call,
  contact,
  deal,
  conversationId,
  title,
  subtitle,
  stateLabel,
  people,
  nameOf,
  guestState,
  openDeal,
  openConversation,
} = useCallInfo();

const root = ref(null);
const { style, startDrag, resetPosition } = useFloating(root);

const tab = ref('keypad');
const number = ref('');
// na ligação: os botões (''), teclado (tons), transferir ou incluir na conferência
const mode = ref('');
const target = ref('');
const streams = ref({});

const inCall = computed(() =>
  ['ringing', 'dialing', 'active'].includes(call.value?.state)
);
const active = computed(() => call.value?.state === 'active');
const conference = computed(() => !!call.value && inConference());
const guests = computed(() => call.value?.others || []);
const canAddGuest = computed(
  () =>
    guests.value.filter(guest => guest.state !== 'ended').length < MAX_GUESTS
);
// na janela do Chatwoot, com o telefone aberto na janela própria
const elsewhere = computed(
  () => phone.popout && !phone.holder && !props.windowed
);
const hint = computed(() =>
  ['offline', 'failed', 'other_tab'].includes(phone.status)
    ? t(`OUTSIDER_VOICE.PHONE.HINTS.${phone.status}`)
    : ''
);
const headerStatus = computed(() => {
  if (conference.value) {
    return t('OUTSIDER_VOICE.CALL.CONFERENCE_PEOPLE', { count: people.value });
  }
  if (inCall.value) return t('OUTSIDER_VOICE.PHONE.STATUS.in_call');
  return t(`OUTSIDER_VOICE.PHONE.STATUS.${phone.status}`);
});
// gravando, dá para pausar mesmo que o cliente tenha saído da conferência
const recordable = computed(
  () => phone.recordingAllowed && (!!call.value?.recording || canRecord())
);
const recordTitle = computed(() => {
  if (!phone.recordingAllowed) return t('OUTSIDER_VOICE.CALL.RECORD_OFF');
  return recordable.value
    ? t('OUTSIDER_VOICE.CALL.RECORD_HINT')
    : t('OUTSIDER_VOICE.CALL.RECORD_CUSTOMER_ONLY');
});
const validTarget = computed(() =>
  mode.value === 'transfer'
    ? /^\d{3}$/.test(target.value)
    : target.value.replace(/\D/g, '').length >= 3
);

const alertError = error => {
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
  return !error;
};

const callTo = value => {
  if (alertError(dial(value))) number.value = '';
};

const pressKey = digit => {
  number.value += digit;
};

const openMode = value => {
  mode.value = mode.value === value ? '' : value;
  target.value = '';
};

const transferTo = extension => {
  transfer(extension);
  mode.value = '';
};

const addGuest = value => {
  if (alertError(addToConference(value))) mode.value = '';
};

const submitTarget = () => {
  if (!validTarget.value) return;
  if (mode.value === 'transfer') transferTo(target.value);
  else addGuest(target.value);
};

const popOut = () => {
  alertError(openPopout(accountId.value));
};

const backToTab = () => window.close();

// barras da voz: só onde está a linha (nas outras abas não há o áudio)
const refreshStreams = () => {
  if (!phone.holder || !call.value) {
    streams.value = {};
    return;
  }
  const list = {};
  [call.value, ...guests.value]
    .filter(party => party.state === 'active')
    .forEach(party => {
      list[party.id] = callStreams(party.id);
    });
  streams.value = list;
};

watch(
  () => [
    phone.holder,
    call.value?.id,
    call.value?.state,
    guests.value.map(guest => `${guest.id}:${guest.state}`).join(),
  ],
  ([, id, state], previous) => {
    if (!previous || previous[1] !== id || previous[2] !== state) {
      mode.value = '';
      target.value = '';
    }
    refreshStreams();
  },
  { immediate: true }
);

// tons pelo teclado do computador com o teclado da ligação aberto
useEventListener(window, 'keydown', event => {
  if (mode.value !== 'keypad' || !active.value || !DTMF.test(event.key)) return;
  if (event.target.closest?.('input, textarea')) return;
  sendDigit(event.key);
});
</script>

<template>
  <div
    ref="root"
    class="flex flex-col overflow-hidden bg-n-solid-2"
    :class="
      windowed
        ? 'w-full h-full'
        : 'fixed z-[60] w-[23.5rem] max-w-[calc(100vw-1rem)] max-h-[calc(100vh-1rem)] border shadow-2xl rounded-2xl border-n-weak'
    "
    :style="windowed ? undefined : style"
    data-testid="outsider-phone-panel"
  >
    <header
      class="flex items-center justify-between gap-2 py-2.5 border-b ltr:pl-4 ltr:pr-2 rtl:pr-4 rtl:pl-2 border-n-weak shrink-0"
      :class="{ 'cursor-move select-none': !windowed }"
      :title="windowed ? undefined : t('OUTSIDER_VOICE.PHONE.DRAG_HINT')"
      data-testid="outsider-phone-header"
      @pointerdown="windowed || startDrag($event)"
      @dblclick="windowed || resetPosition()"
    >
      <div class="flex items-center min-w-0 gap-2">
        <Icon
          v-if="!windowed"
          icon="i-lucide-grip-vertical"
          class="size-4 shrink-0 text-n-slate-9"
        />
        <div class="min-w-0">
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PHONE.TITLE') }}
            <span class="font-normal text-n-slate-11">
              ·
              {{
                t('OUTSIDER_VOICE.PHONE.EXTENSION', {
                  extension: phone.extension,
                })
              }}
            </span>
          </div>
          <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
            <span
              class="rounded-full size-2 shrink-0"
              :class="DOT[phone.status]"
            />
            <span class="truncate">{{ headerStatus }}</span>
          </div>
        </div>
      </div>
      <div class="flex items-center gap-1 shrink-0">
        <Button
          v-if="windowed"
          sm
          ghost
          slate
          icon="i-lucide-square-arrow-down-left"
          :title="t('OUTSIDER_VOICE.PHONE.BACK_TO_TAB')"
          :disabled="inCall"
          data-testid="outsider-phone-back"
          @click="backToTab"
        />
        <template v-else>
          <Button
            v-if="!elsewhere"
            sm
            ghost
            slate
            icon="i-lucide-square-arrow-out-up-right"
            :title="
              inCall
                ? t('OUTSIDER_VOICE.PHONE.POPOUT_IN_CALL')
                : t('OUTSIDER_VOICE.PHONE.POPOUT')
            "
            :disabled="inCall"
            data-testid="outsider-phone-popout"
            @click="popOut"
          />
          <Button
            sm
            ghost
            slate
            icon="i-lucide-minus"
            :title="t('OUTSIDER_VOICE.PHONE.MINIMIZE')"
            data-testid="outsider-phone-minimize"
            @click="setPanelOpen(false)"
          />
        </template>
      </div>
    </header>

    <div class="flex flex-col flex-1 min-h-0 gap-3 p-4 overflow-y-auto">
      <!-- o telefone está na janela própria -->
      <div
        v-if="elsewhere && !call"
        class="flex flex-col items-center gap-3 py-4 text-center"
        data-testid="outsider-phone-elsewhere"
      >
        <span
          class="flex items-center justify-center rounded-full size-12 bg-n-alpha-2"
        >
          <Icon icon="i-lucide-app-window" class="size-6 text-n-slate-11" />
        </span>
        <p class="mb-0 text-sm text-n-slate-12">
          {{ t('OUTSIDER_VOICE.PHONE.ELSEWHERE') }}
        </p>
        <div class="flex flex-wrap justify-center gap-2">
          <Button
            sm
            icon="i-lucide-app-window"
            :label="t('OUTSIDER_VOICE.PHONE.SHOW_WINDOW')"
            @click="showPopout"
          />
          <Button
            sm
            slate
            faded
            icon="i-lucide-monitor-smartphone"
            :label="t('OUTSIDER_VOICE.PHONE.BRING_HERE')"
            @click="useThisTab"
          />
        </div>
      </div>

      <!-- sem conexão, recusado ou em outra aba -->
      <template v-else-if="hint && !inCall">
        <p class="mb-0 text-sm text-n-slate-11">{{ hint }}</p>
        <Button
          v-if="phone.status === 'other_tab'"
          :label="t('OUTSIDER_VOICE.PHONE.USE_HERE')"
          icon="i-lucide-monitor-smartphone"
          @click="useThisTab"
        />
        <Button
          v-else
          slate
          :label="t('OUTSIDER_VOICE.PHONE.RECONNECT')"
          icon="i-lucide-refresh-cw"
          @click="restartPhone"
        />
      </template>

      <!-- ligação -->
      <template v-else-if="call">
        <!-- conferência: quem está na conversa -->
        <div
          v-if="conference"
          class="flex flex-col gap-1"
          data-testid="outsider-conference"
        >
          <div
            v-for="party in [call, ...guests]"
            :key="party.id"
            class="flex items-center gap-2.5 px-2 py-1.5 rounded-xl"
            :class="party.state === 'ended' ? 'opacity-50' : 'bg-n-alpha-1'"
            data-testid="outsider-conference-party"
          >
            <Avatar
              :size="32"
              :name="nameOf(party)"
              :src="party.lookup?.contact?.thumbnail || ''"
              rounded-full
              class="shrink-0"
              :class="{ 'animate-pulse': party.state === 'dialing' }"
            />
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate text-n-slate-12">
                {{ nameOf(party) }}
              </div>
              <div class="text-xs truncate tabular-nums text-n-slate-11">
                {{ party.id === call.id ? stateLabel : guestState(party) }}
              </div>
            </div>
            <AudioLevel
              v-if="streams[party.id]"
              :stream="streams[party.id].remote"
            />
            <Button
              v-if="party.state !== 'ended'"
              xs
              ghost
              ruby
              icon="i-lucide-x"
              :title="t('OUTSIDER_VOICE.CALL.REMOVE')"
              data-testid="outsider-conference-remove"
              @click="removeFromConference(party.id)"
            />
          </div>
        </div>

        <!-- uma pessoa -->
        <div
          v-else
          class="flex flex-col items-center gap-1 pt-1 text-center"
          data-testid="outsider-call-card"
        >
          <Avatar
            :size="72"
            :name="title"
            :src="contact?.thumbnail || ''"
            rounded-full
            :class="{ 'animate-pulse': call.state === 'ringing' }"
          />
          <div class="mt-2 text-lg font-medium leading-6 text-n-slate-12">
            {{ title }}
          </div>
          <div class="text-sm text-n-slate-11">{{ subtitle }}</div>
          <div
            class="flex items-center gap-1.5 text-sm font-medium tabular-nums"
            :class="{
              'text-n-teal-11': active && !call.held,
              'text-n-amber-11':
                ['ringing', 'dialing'].includes(call.state) || call.held,
              'text-n-slate-11': call.state === 'ended',
            }"
            data-testid="outsider-call-state"
          >
            <Icon v-if="active" icon="i-lucide-signal" class="size-4" />
            {{ stateLabel }}
            <span v-if="active && !call.held" class="font-normal">
              · {{ t('OUTSIDER_VOICE.CALL.CONNECTED') }}
            </span>
          </div>
        </div>

        <div
          v-if="call.recording"
          class="flex items-center self-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full"
          :class="
            call.recording === 'on'
              ? 'bg-n-ruby-3 text-n-ruby-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          data-testid="outsider-call-recording"
        >
          <span
            class="rounded-full size-2"
            :class="
              call.recording === 'on'
                ? 'bg-n-ruby-9 animate-pulse'
                : 'bg-n-slate-8'
            "
          />
          {{
            call.recording === 'on'
              ? t('OUTSIDER_VOICE.CALL.RECORDING_ON')
              : t('OUTSIDER_VOICE.CALL.RECORDING_PAUSED')
          }}
        </div>

        <div
          v-if="active && !conference && streams[call.id]"
          class="flex items-center justify-center gap-6 text-xs text-n-slate-11"
          data-testid="outsider-call-levels"
        >
          <span class="flex items-center gap-2">
            {{ t('OUTSIDER_VOICE.CALL.YOU') }}
            <AudioLevel
              :stream="call.muted ? null : streams[call.id].local"
              color="bg-n-blue-9"
            />
          </span>
          <span class="flex items-center gap-2">
            <AudioLevel :stream="streams[call.id].remote" />
            {{ t('OUTSIDER_VOICE.CALL.OTHER_SIDE') }}
          </span>
        </div>

        <div
          v-if="(deal || conversationId) && !conference"
          class="flex flex-wrap justify-center gap-1.5"
        >
          <button
            v-if="deal"
            type="button"
            class="flex items-center min-w-0 gap-1.5 px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
            :title="t('OUTSIDER_VOICE.CALL.OPEN_DEAL')"
            @click="openDeal"
          >
            <Icon icon="i-lucide-kanban" class="size-3.5 text-n-slate-11" />
            <span class="truncate">
              {{
                t('OUTSIDER_VOICE.CALL.DEAL', {
                  title: deal.title,
                  stage: deal.stage,
                })
              }}
            </span>
          </button>
          <button
            v-if="conversationId"
            type="button"
            class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
            @click="openConversation"
          >
            <Icon
              icon="i-lucide-message-circle"
              class="size-3.5 text-n-slate-11"
            />
            {{ t('OUTSIDER_VOICE.CALL.OPEN_CONVERSATION') }}
          </button>
        </div>

        <!-- tocando -->
        <div
          v-if="call.state === 'ringing'"
          class="grid grid-cols-2 gap-3 pt-2"
        >
          <button
            type="button"
            class="flex items-center justify-center gap-2 text-base font-medium text-white h-14 rounded-xl bg-n-ruby-9 hover:bg-n-ruby-10"
            data-testid="outsider-call-reject"
            @click="hangup"
          >
            <Icon icon="i-lucide-phone-off" class="size-6" />
            {{ t('OUTSIDER_VOICE.CALL.REJECT') }}
          </button>
          <button
            type="button"
            class="flex items-center justify-center gap-2 text-base font-medium text-white h-14 rounded-xl bg-n-teal-9 hover:bg-n-teal-10"
            data-testid="outsider-call-answer"
            @click="answer"
          >
            <Icon icon="i-lucide-phone" class="size-6" />
            {{ t('OUTSIDER_VOICE.CALL.ANSWER') }}
          </button>
        </div>

        <template v-else-if="call.state !== 'ended'">
          <!-- os botões da ligação -->
          <div
            v-if="!mode"
            class="grid grid-cols-3 gap-2"
            data-testid="outsider-call-actions"
          >
            <CallAction
              :icon="call.held ? 'i-lucide-play' : 'i-lucide-pause'"
              :label="
                call.held
                  ? t('OUTSIDER_VOICE.CALL.RESUME')
                  : t('OUTSIDER_VOICE.CALL.HOLD')
              "
              :active="call.held"
              :disabled="!active || conference"
              data-testid="outsider-call-hold"
              @click="toggleHold"
            />
            <CallAction
              :icon="call.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
              :label="
                call.muted
                  ? t('OUTSIDER_VOICE.CALL.UNMUTE')
                  : t('OUTSIDER_VOICE.CALL.MUTE')
              "
              :active="call.muted"
              :disabled="!active"
              data-testid="outsider-call-mute"
              @click="toggleMute"
            />
            <CallAction
              icon="i-lucide-user-plus"
              :label="t('OUTSIDER_VOICE.CALL.CONFERENCE')"
              :disabled="!active || !canAddGuest"
              data-testid="outsider-call-conference"
              @click="openMode('conference')"
            />
            <CallAction
              icon="i-lucide-arrow-right-left"
              :label="t('OUTSIDER_VOICE.CALL.TRANSFER')"
              :disabled="!active || !!call.transferTo || conference"
              data-testid="outsider-call-transfer"
              @click="openMode('transfer')"
            />
            <CallAction
              icon="i-lucide-grid-3x3"
              :label="t('OUTSIDER_VOICE.CALL.KEYPAD')"
              :disabled="!active"
              data-testid="outsider-call-keypad"
              @click="openMode('keypad')"
            />
            <CallAction
              :icon="
                call.recording === 'on'
                  ? 'i-lucide-circle-pause'
                  : 'i-lucide-audio-lines'
              "
              :label="
                call.recording === 'on'
                  ? t('OUTSIDER_VOICE.CALL.RECORD_PAUSE')
                  : call.recording === 'paused'
                    ? t('OUTSIDER_VOICE.CALL.RECORD_RESUME')
                    : t('OUTSIDER_VOICE.CALL.RECORD')
              "
              :active="call.recording === 'on'"
              tone="ruby"
              :disabled="!active || !recordable"
              :title="recordTitle"
              data-testid="outsider-call-record"
              @click="toggleRecording"
            />
          </div>

          <!-- teclado, transferir ou incluir -->
          <div v-else class="flex flex-col gap-2">
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t(`OUTSIDER_VOICE.CALL.MODES.${mode.toUpperCase()}`) }}
              </span>
              <Button
                xs
                ghost
                slate
                icon="i-lucide-arrow-left"
                :label="t('OUTSIDER_VOICE.CALL.BACK')"
                data-testid="outsider-call-mode-back"
                @click="mode = ''"
              />
            </div>
            <PhoneKeypad v-if="mode === 'keypad'" @press="sendDigit" />
            <template v-else>
              <span class="text-xs text-n-slate-11">
                {{
                  mode === 'transfer'
                    ? t('OUTSIDER_VOICE.CALL.TRANSFER_HINT')
                    : t('OUTSIDER_VOICE.CALL.CONFERENCE_HINT', {
                        max: MAX_GUESTS + 1,
                      })
                }}
              </span>
              <form
                class="flex items-center gap-1.5"
                @submit.prevent="submitTarget"
              >
                <input
                  v-model="target"
                  :inputmode="mode === 'transfer' ? 'numeric' : 'tel'"
                  :maxlength="mode === 'transfer' ? 3 : 20"
                  :placeholder="
                    mode === 'transfer'
                      ? t('OUTSIDER_VOICE.CALL.TRANSFER_PLACEHOLDER')
                      : t('OUTSIDER_VOICE.PHONE.NUMBER_PLACEHOLDER')
                  "
                  class="flex-1 min-w-0 !mb-0 h-10 px-3 text-base rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
                  data-testid="outsider-call-target"
                />
                <Button
                  type="submit"
                  :label="
                    mode === 'transfer'
                      ? t('OUTSIDER_VOICE.CALL.TRANSFER')
                      : t('OUTSIDER_VOICE.CALL.ADD')
                  "
                  :disabled="!validTarget"
                  data-testid="outsider-call-target-submit"
                />
              </form>
              <TeamList
                :icon="
                  mode === 'transfer'
                    ? 'i-lucide-arrow-right-left'
                    : 'i-lucide-user-plus'
                "
                :exclude="[call.number, ...guests.map(guest => guest.number)]"
                @pick="
                  mode === 'transfer' ? transferTo($event) : addGuest($event)
                "
              />
            </template>
          </div>

          <button
            type="button"
            class="flex items-center justify-center w-full gap-2 text-base font-medium text-white h-14 shrink-0 rounded-xl bg-n-ruby-9 hover:bg-n-ruby-10"
            data-testid="outsider-call-hangup"
            @click="hangup"
          >
            <Icon icon="i-lucide-phone-off" class="size-6" />
            {{
              conference
                ? t('OUTSIDER_VOICE.CALL.HANGUP_ALL')
                : t('OUTSIDER_VOICE.CALL.HANGUP')
            }}
          </button>
        </template>

        <Button
          v-else
          slate
          faded
          :label="t('OUTSIDER_VOICE.CALL.CLOSE')"
          @click="clearEndedCall"
        />
      </template>

      <!-- sem ligação: teclado ou equipe -->
      <template v-else-if="phone.status === 'ready'">
        <div class="grid grid-cols-2 gap-1 p-1 rounded-xl bg-n-alpha-1">
          <button
            v-for="key in ['keypad', 'team']"
            :key="key"
            type="button"
            class="flex items-center justify-center gap-1.5 py-2 text-sm rounded-lg"
            :class="
              tab === key
                ? 'bg-n-solid-3 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`outsider-phone-tab-${key}`"
            @click="tab = key"
          >
            <Icon
              :icon="key === 'keypad' ? 'i-lucide-grid-3x3' : 'i-lucide-users'"
              class="size-4"
            />
            {{ t(`OUTSIDER_VOICE.PHONE.TABS.${key.toUpperCase()}`) }}
          </button>
        </div>

        <template v-if="tab === 'keypad'">
          <form
            class="flex items-center gap-1"
            @submit.prevent="callTo(number)"
          >
            <input
              v-model="number"
              type="tel"
              autocomplete="off"
              :placeholder="t('OUTSIDER_VOICE.PHONE.NUMBER_PLACEHOLDER')"
              class="flex-1 min-w-0 !mb-0 h-12 px-3 text-2xl font-medium tracking-wide text-center rounded-xl reset-base bg-n-alpha-black2 text-n-slate-12 placeholder:text-base placeholder:font-normal placeholder:tracking-normal outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
              data-testid="outsider-phone-number"
            />
            <Button
              v-if="number"
              type="button"
              ghost
              slate
              icon="i-lucide-delete"
              :title="t('OUTSIDER_VOICE.PHONE.CLEAR')"
              @click="number = number.slice(0, -1)"
            />
          </form>
          <PhoneKeypad @press="pressKey" />
          <button
            type="button"
            class="flex items-center justify-center w-full gap-2 text-base font-medium text-white h-14 rounded-xl bg-n-teal-9 hover:bg-n-teal-10 disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="!number"
            data-testid="outsider-phone-call"
            @click="callTo(number)"
          >
            <Icon icon="i-lucide-phone" class="size-6" />
            {{ t('OUTSIDER_VOICE.PHONE.CALL') }}
          </button>
          <button
            type="button"
            class="flex items-start gap-2 p-2 text-left rounded-lg hover:bg-n-alpha-2"
            data-testid="outsider-phone-echo"
            @click="callTo(phone.echoExtension)"
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
        <TeamList v-else @pick="callTo" />
      </template>
    </div>
  </div>
</template>
