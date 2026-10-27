<script setup>
// OUTSIDER: a ligação com o telefone minimizado (Entrega 23): cartão pequeno com quem é, o tempo, as barras
// da voz do outro lado e os botões principais; o botão de expandir abre o telefone (ou mostra a janela
// própria dele, quando está nela). Fica onde o telefone estava (arrastado) e também arrasta.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import AudioLevel from './AudioLevel.vue';
import { useCallInfo } from './useCallInfo';
import { useFloating } from './useFloating';
import {
  phone,
  setPanelOpen,
  showPopout,
  answer,
  hangup,
  toggleMute,
  inConference,
  callStreams,
  clearEndedCall,
} from './phone';

const { t } = useI18n();
const { call, contact, title, stateLabel, people } = useCallInfo();

const root = ref(null);
const { style, startDrag } = useFloating(root);

const conference = computed(() => !!call.value && inConference());

const expand = () => {
  if (phone.popout && !phone.holder) showPopout();
  else setPanelOpen(true);
};

const remote = ref(null);
watch(
  () => [call.value?.state, call.value?.id, phone.holder],
  ([state]) => {
    remote.value =
      state === 'active' && phone.holder ? callStreams().remote : null;
  },
  { immediate: true }
);
</script>

<template>
  <div
    ref="root"
    class="fixed z-[60] w-80 max-w-[calc(100vw-1rem)] flex flex-col gap-2 p-3 border shadow-xl rounded-2xl border-n-weak bg-n-solid-2"
    :class="{ 'outline outline-2 outline-n-amber-9': call.state === 'ringing' }"
    :style="style"
    data-testid="outsider-call-mini"
  >
    <div
      class="flex items-center gap-3 cursor-move select-none"
      @pointerdown="startDrag"
    >
      <Avatar
        :size="36"
        :name="title"
        :src="contact?.thumbnail || ''"
        rounded-full
        class="shrink-0"
        :class="{ 'animate-pulse': call.state === 'ringing' }"
      />
      <div class="flex-1 min-w-0">
        <div
          class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
        >
          <span class="truncate">{{ title }}</span>
          <span
            v-if="conference"
            class="px-1.5 text-xs rounded-full shrink-0 bg-n-alpha-2 text-n-slate-11"
          >
            +{{ people - 1 }}
          </span>
          <span
            v-if="call.recording === 'on'"
            class="rounded-full size-2 shrink-0 bg-n-ruby-9 animate-pulse"
            :title="t('OUTSIDER_VOICE.CALL.RECORDING_ON')"
          />
        </div>
        <div
          class="text-xs tabular-nums truncate"
          :class="
            call.state === 'active' && !call.held
              ? 'text-n-teal-11'
              : 'text-n-amber-11'
          "
          data-testid="outsider-call-state"
        >
          {{ stateLabel }}
        </div>
      </div>
      <AudioLevel v-if="remote" :stream="remote" />
      <Button
        xs
        ghost
        slate
        :icon="
          phone.popout && !phone.holder
            ? 'i-lucide-app-window'
            : 'i-lucide-maximize-2'
        "
        :title="t('OUTSIDER_VOICE.CALL.EXPAND')"
        data-testid="outsider-call-expand"
        @click="expand"
      />
    </div>

    <div v-if="call.state === 'ringing'" class="grid grid-cols-2 gap-2">
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 h-10 text-sm font-medium text-white rounded-lg bg-n-ruby-9 hover:bg-n-ruby-10"
        data-testid="outsider-call-reject"
        @click="hangup"
      >
        <Icon icon="i-lucide-phone-off" class="size-4" />
        {{ t('OUTSIDER_VOICE.CALL.REJECT') }}
      </button>
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 h-10 text-sm font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10"
        data-testid="outsider-call-answer"
        @click="answer"
      >
        <Icon icon="i-lucide-phone" class="size-4" />
        {{ t('OUTSIDER_VOICE.CALL.ANSWER') }}
      </button>
    </div>
    <div
      v-else-if="call.state !== 'ended'"
      class="grid grid-cols-[auto_1fr] gap-2"
    >
      <button
        type="button"
        class="flex items-center justify-center h-10 px-3 rounded-lg disabled:opacity-40"
        :class="
          call.muted
            ? 'bg-n-amber-9 text-black'
            : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3'
        "
        :disabled="call.state !== 'active'"
        :title="
          call.muted
            ? t('OUTSIDER_VOICE.CALL.UNMUTE')
            : t('OUTSIDER_VOICE.CALL.MUTE')
        "
        data-testid="outsider-call-mute"
        @click="toggleMute"
      >
        <Icon
          :icon="call.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
          class="size-5"
        />
      </button>
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 h-10 text-sm font-medium text-white rounded-lg bg-n-ruby-9 hover:bg-n-ruby-10"
        data-testid="outsider-call-hangup"
        @click="hangup"
      >
        <Icon icon="i-lucide-phone-off" class="size-4" />
        {{
          conference
            ? t('OUTSIDER_VOICE.CALL.HANGUP_ALL')
            : t('OUTSIDER_VOICE.CALL.HANGUP')
        }}
      </button>
    </div>
    <div v-else class="flex justify-end">
      <Button
        xs
        ghost
        slate
        :label="t('OUTSIDER_VOICE.CALL.CLOSE')"
        @click="clearEndedCall"
      />
    </div>
  </div>
</template>
