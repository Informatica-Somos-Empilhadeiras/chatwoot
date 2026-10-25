<script setup>
// OUTSIDER: a ligação com o telefone minimizado (Entrega 23): cartão pequeno no canto da tela com quem é, o
// tempo, as barras da voz do outro lado e os botões principais; o botão de expandir abre o telefone.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AudioLevel from './AudioLevel.vue';
import { useCallInfo } from './useCallInfo';
import {
  setPanelOpen,
  answer,
  hangup,
  toggleMute,
  callStreams,
  clearEndedCall,
} from './phone';

const { t } = useI18n();
const { call, contact, title, stateLabel } = useCallInfo();

const remote = ref(null);
watch(
  () => call.value?.state,
  state => {
    remote.value = state === 'active' ? callStreams().remote : null;
  },
  { immediate: true }
);
</script>

<template>
  <div
    class="fixed z-[60] bottom-4 ltr:right-4 rtl:left-4 w-80 max-w-[calc(100vw-2rem)] flex flex-col gap-2 p-3 border shadow-xl rounded-2xl border-n-weak bg-n-solid-2"
    :class="{ 'outline outline-2 outline-n-amber-9': call.state === 'ringing' }"
    data-testid="outsider-call-mini"
  >
    <div class="flex items-center gap-3">
      <Avatar
        :size="36"
        :name="title"
        :src="contact?.thumbnail || ''"
        rounded-full
        class="shrink-0"
        :class="{ 'animate-pulse': call.state === 'ringing' }"
      />
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium truncate text-n-slate-12">
          {{ title }}
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
      <AudioLevel v-if="call.state === 'active'" :stream="remote" />
      <Button
        xs
        ghost
        slate
        icon="i-lucide-maximize-2"
        :title="t('OUTSIDER_VOICE.CALL.EXPAND')"
        data-testid="outsider-call-expand"
        @click="setPanelOpen(true)"
      />
    </div>

    <div v-if="call.state === 'ringing'" class="grid grid-cols-2 gap-2">
      <Button
        sm
        ruby
        icon="i-lucide-phone-off"
        :label="t('OUTSIDER_VOICE.CALL.REJECT')"
        data-testid="outsider-call-reject"
        @click="hangup"
      />
      <Button
        sm
        teal
        icon="i-lucide-phone"
        :label="t('OUTSIDER_VOICE.CALL.ANSWER')"
        data-testid="outsider-call-answer"
        @click="answer"
      />
    </div>
    <div
      v-else-if="call.state !== 'ended'"
      class="flex items-center justify-end gap-2"
    >
      <Button
        v-if="call.state === 'active'"
        sm
        :variant="call.muted ? 'solid' : 'faded'"
        :color="call.muted ? 'amber' : 'slate'"
        :icon="call.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
        :title="
          call.muted
            ? t('OUTSIDER_VOICE.CALL.UNMUTE')
            : t('OUTSIDER_VOICE.CALL.MUTE')
        "
        data-testid="outsider-call-mute"
        @click="toggleMute"
      />
      <Button
        sm
        ruby
        icon="i-lucide-phone-off"
        :label="t('OUTSIDER_VOICE.CALL.HANGUP')"
        data-testid="outsider-call-hangup"
        @click="hangup"
      />
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
