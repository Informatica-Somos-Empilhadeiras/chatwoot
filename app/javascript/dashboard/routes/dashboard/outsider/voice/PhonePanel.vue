<script setup>
// OUTSIDER: o telefone aberto e fixo no canto da tela (Entrega 23); só some ao minimizar. Sem ligação:
// teclado para discar e a equipe (colegas com o telefone conectado). Na ligação: quem é, tempo, as barras
// que mexem com a voz (você e o outro lado), mudo, espera, teclado, transferir para outro ramal e encerrar.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PhoneKeypad from './PhoneKeypad.vue';
import TeamList from './TeamList.vue';
import AudioLevel from './AudioLevel.vue';
import { useCallInfo } from './useCallInfo';
import {
  phone,
  setPanelOpen,
  dial,
  answer,
  hangup,
  toggleMute,
  toggleHold,
  transfer,
  sendDigit,
  callStreams,
  clearEndedCall,
  restartPhone,
  useThisTab,
} from './phone';

const DOT = {
  ready: 'bg-n-teal-9',
  connecting: 'bg-n-amber-9',
  offline: 'bg-n-ruby-9',
  failed: 'bg-n-ruby-9',
  other_tab: 'bg-n-slate-8',
};

const { t } = useI18n();
const {
  call,
  contact,
  deal,
  conversationId,
  title,
  subtitle,
  stateLabel,
  openDeal,
  openConversation,
} = useCallInfo();

const tab = ref('keypad');
const number = ref('');
// na ligação: nada, teclado (tons) ou transferir
const mode = ref('');
const transferTarget = ref('');
const streams = ref({ local: null, remote: null });

const canTransfer = computed(() => /^\d{3}$/.test(transferTarget.value));

const inCall = computed(() =>
  ['ringing', 'dialing', 'active'].includes(call.value?.state)
);
const hint = computed(() =>
  ['offline', 'failed', 'other_tab'].includes(phone.status)
    ? t(`OUTSIDER_VOICE.PHONE.HINTS.${phone.status}`)
    : ''
);

const callTo = target => {
  const error = dial(target);
  if (error) {
    useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
    return;
  }
  number.value = '';
};

const pressKey = digit => {
  number.value += digit;
};

const toggleMode = value => {
  mode.value = mode.value === value ? '' : value;
};

const transferTo = extension => {
  transfer(extension);
  mode.value = '';
};

watch(
  () => call.value?.state,
  state => {
    mode.value = '';
    transferTarget.value = '';
    streams.value =
      state === 'active' ? callStreams() : { local: null, remote: null };
  }
);

const tile = active =>
  active
    ? 'bg-n-amber-3 text-n-amber-11'
    : 'bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12';
</script>

<template>
  <div
    class="fixed z-[60] bottom-4 ltr:right-4 rtl:left-4 w-[22rem] max-w-[calc(100vw-2rem)] max-h-[calc(100vh-2rem)] flex flex-col overflow-hidden border shadow-xl rounded-2xl border-n-weak bg-n-solid-2"
    data-testid="outsider-phone-panel"
  >
    <header
      class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
    >
      <div class="min-w-0">
        <div class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_VOICE.PHONE.TITLE') }}
        </div>
        <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
          <span class="rounded-full size-2" :class="DOT[phone.status]" />
          {{ t(`OUTSIDER_VOICE.PHONE.STATUS.${phone.status}`) }}
          ·
          {{
            t('OUTSIDER_VOICE.PHONE.EXTENSION', { extension: phone.extension })
          }}
        </div>
      </div>
      <Button
        xs
        ghost
        slate
        icon="i-lucide-minus"
        :title="t('OUTSIDER_VOICE.PHONE.MINIMIZE')"
        data-testid="outsider-phone-minimize"
        @click="setPanelOpen(false)"
      />
    </header>

    <div class="flex flex-col flex-1 gap-3 p-4 overflow-y-auto">
      <!-- sem conexão, recusado ou em outra aba -->
      <template v-if="hint && !inCall">
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

      <!-- ligação -->
      <template v-else-if="call">
        <div
          class="flex flex-col items-center gap-1 text-center"
          data-testid="outsider-call-card"
        >
          <Avatar
            :size="56"
            :name="title"
            :src="contact?.thumbnail || ''"
            rounded-full
            :class="{ 'animate-pulse': call.state === 'ringing' }"
          />
          <div class="mt-1 text-base font-medium text-n-slate-12">
            {{ title }}
          </div>
          <div class="text-xs text-n-slate-11">{{ subtitle }}</div>
          <div
            class="text-sm font-medium tabular-nums"
            :class="{
              'text-n-teal-11': call.state === 'active' && !call.held,
              'text-n-amber-11':
                ['ringing', 'dialing'].includes(call.state) || call.held,
              'text-n-slate-11': call.state === 'ended',
            }"
            data-testid="outsider-call-state"
          >
            {{ stateLabel }}
          </div>
        </div>

        <div
          v-if="call.state === 'active'"
          class="flex items-center justify-center gap-6 text-xs text-n-slate-11"
          data-testid="outsider-call-levels"
        >
          <span class="flex items-center gap-2">
            {{ t('OUTSIDER_VOICE.CALL.YOU') }}
            <AudioLevel
              :stream="call.muted ? null : streams.local"
              color="bg-n-blue-9"
            />
          </span>
          <span class="flex items-center gap-2">
            <AudioLevel :stream="streams.remote" />
            {{ t('OUTSIDER_VOICE.CALL.OTHER_SIDE') }}
          </span>
        </div>

        <div
          v-if="deal || conversationId"
          class="flex flex-wrap justify-center gap-1.5"
        >
          <button
            v-if="deal"
            type="button"
            class="flex items-center min-w-0 gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
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
            class="flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
            @click="openConversation"
          >
            <Icon
              icon="i-lucide-message-circle"
              class="size-3.5 text-n-slate-11"
            />
            {{ t('OUTSIDER_VOICE.CALL.OPEN_CONVERSATION') }}
          </button>
        </div>

        <div v-if="call.state === 'ringing'" class="grid grid-cols-2 gap-2">
          <Button
            ruby
            icon="i-lucide-phone-off"
            :label="t('OUTSIDER_VOICE.CALL.REJECT')"
            data-testid="outsider-call-reject"
            @click="hangup"
          />
          <Button
            teal
            icon="i-lucide-phone"
            :label="t('OUTSIDER_VOICE.CALL.ANSWER')"
            data-testid="outsider-call-answer"
            @click="answer"
          />
        </div>

        <template v-else-if="call.state !== 'ended'">
          <div class="grid grid-cols-4 gap-2">
            <button
              type="button"
              class="flex flex-col items-center gap-1 py-2.5 text-xs rounded-xl disabled:opacity-40"
              :class="tile(call.muted)"
              :disabled="call.state !== 'active'"
              data-testid="outsider-call-mute"
              @click="toggleMute"
            >
              <Icon
                :icon="call.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
                class="size-5"
              />
              {{
                call.muted
                  ? t('OUTSIDER_VOICE.CALL.UNMUTE')
                  : t('OUTSIDER_VOICE.CALL.MUTE')
              }}
            </button>
            <button
              type="button"
              class="flex flex-col items-center gap-1 py-2.5 text-xs rounded-xl disabled:opacity-40"
              :class="tile(call.held)"
              :disabled="call.state !== 'active'"
              data-testid="outsider-call-hold"
              @click="toggleHold"
            >
              <Icon
                :icon="call.held ? 'i-lucide-play' : 'i-lucide-pause'"
                class="size-5"
              />
              {{
                call.held
                  ? t('OUTSIDER_VOICE.CALL.RESUME')
                  : t('OUTSIDER_VOICE.CALL.HOLD')
              }}
            </button>
            <button
              type="button"
              class="flex flex-col items-center gap-1 py-2.5 text-xs rounded-xl disabled:opacity-40"
              :class="tile(mode === 'keypad')"
              :disabled="call.state !== 'active'"
              @click="toggleMode('keypad')"
            >
              <Icon icon="i-lucide-grid-3x3" class="size-5" />
              {{ t('OUTSIDER_VOICE.CALL.KEYPAD') }}
            </button>
            <button
              type="button"
              class="flex flex-col items-center gap-1 py-2.5 text-xs rounded-xl disabled:opacity-40"
              :class="tile(mode === 'transfer')"
              :disabled="call.state !== 'active' || !!call.transferTo"
              data-testid="outsider-call-transfer"
              @click="toggleMode('transfer')"
            >
              <Icon icon="i-lucide-arrow-right-left" class="size-5" />
              {{ t('OUTSIDER_VOICE.CALL.TRANSFER') }}
            </button>
          </div>

          <PhoneKeypad v-if="mode === 'keypad'" @press="sendDigit" />

          <div
            v-if="mode === 'transfer'"
            class="flex flex-col gap-2 p-2 rounded-xl bg-n-alpha-1"
          >
            <span class="px-1 text-xs text-n-slate-11">
              {{ t('OUTSIDER_VOICE.CALL.TRANSFER_HINT') }}
            </span>
            <form
              class="flex items-center gap-1.5"
              @submit.prevent="transferTo(transferTarget)"
            >
              <input
                v-model="transferTarget"
                inputmode="numeric"
                maxlength="3"
                :placeholder="t('OUTSIDER_VOICE.CALL.TRANSFER_PLACEHOLDER')"
                class="flex-1 min-w-0 !mb-0 h-8 px-3 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
              />
              <Button
                type="submit"
                xs
                :label="t('OUTSIDER_VOICE.CALL.TRANSFER')"
                :disabled="!canTransfer"
              />
            </form>
            <TeamList
              icon="i-lucide-arrow-right-left"
              :exclude="call.number"
              @pick="transferTo"
            />
          </div>

          <Button
            ruby
            icon="i-lucide-phone-off"
            :label="t('OUTSIDER_VOICE.CALL.HANGUP')"
            data-testid="outsider-call-hangup"
            @click="hangup"
          />
        </template>

        <Button
          v-else
          sm
          slate
          faded
          :label="t('OUTSIDER_VOICE.CALL.CLOSE')"
          @click="clearEndedCall"
        />
      </template>

      <!-- sem ligação: teclado ou equipe -->
      <template v-else-if="phone.status === 'ready'">
        <div class="grid grid-cols-2 gap-1 p-0.5 rounded-lg bg-n-alpha-1">
          <button
            v-for="key in ['keypad', 'team']"
            :key="key"
            type="button"
            class="py-1.5 text-sm rounded-md"
            :class="
              tab === key
                ? 'bg-n-solid-3 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11'
            "
            :data-testid="`outsider-phone-tab-${key}`"
            @click="tab = key"
          >
            {{ t(`OUTSIDER_VOICE.PHONE.TABS.${key.toUpperCase()}`) }}
          </button>
        </div>

        <template v-if="tab === 'keypad'">
          <form
            class="flex items-center gap-1.5"
            @submit.prevent="callTo(number)"
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
          <PhoneKeypad @press="pressKey" />
          <Button
            teal
            icon="i-lucide-phone"
            :label="t('OUTSIDER_VOICE.PHONE.CALL')"
            :disabled="!number"
            data-testid="outsider-phone-call"
            @click="callTo(number)"
          />
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
