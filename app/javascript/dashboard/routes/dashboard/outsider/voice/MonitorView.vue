<script setup>
// OUTSIDER: o telefone de quem está monitorando a ligação de outra pessoa (Entrega 26).
// Ouvindo em silêncio: ninguém percebe; o microfone fica desligado. "Sussurrar" entra falando só com o atendente.
// Sussurrando: o cliente não ouve. O supervisor passa a falar com todos quando quiser; o convidado pede e espera o
// atendente permitir. "Voltar a sussurrar" deixa de falar com o cliente.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CallAction from './CallAction.vue';
import { requestWhisperMode, switchToWhisper, toggleMute } from './phone';

const props = defineProps({
  call: { type: Object, required: true },
});

const { t } = useI18n();

const monitor = computed(() => props.call.monitor);
const active = computed(() => props.call.state === 'active');
const listening = computed(() => monitor.value.mode === 'listen');
const status = computed(() => {
  if (listening.value) return 'LISTENING';
  return monitor.value.open ? 'OPEN' : 'WHISPERING';
});
const hint = computed(() => {
  if (listening.value) return t('OUTSIDER_VOICE.MONITOR.LISTEN_HINT');
  if (monitor.value.pending) {
    return t('OUTSIDER_VOICE.MONITOR.WAITING', { name: monitor.value.name });
  }
  return monitor.value.open
    ? t('OUTSIDER_VOICE.MONITOR.OPEN_HINT')
    : t('OUTSIDER_VOICE.MONITOR.WHISPER_HINT', { name: monitor.value.name });
});
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="outsider-monitor">
    <div
      class="flex items-start gap-2 px-3 py-2 text-xs rounded-xl"
      :class="
        listening
          ? 'bg-n-slate-3 text-n-slate-11'
          : monitor.open
            ? 'bg-n-amber-3 text-n-amber-11'
            : 'bg-n-violet-3 text-n-violet-11'
      "
    >
      <Icon
        :icon="
          listening
            ? 'i-lucide-ghost'
            : monitor.open
              ? 'i-lucide-users'
              : 'i-lucide-ear'
        "
        class="size-4 shrink-0 mt-0.5"
      />
      <span class="flex flex-col gap-0.5">
        <span class="font-medium">
          {{ t(`OUTSIDER_VOICE.MONITOR.${status}`) }}
        </span>
        <span>{{ hint }}</span>
      </span>
    </div>
    <div class="grid grid-cols-2 gap-2">
      <CallAction
        v-if="listening"
        icon="i-lucide-ear"
        :label="t('OUTSIDER_VOICE.MONITOR.WHISPER_BTN')"
        :disabled="!active"
        data-testid="outsider-monitor-whisper"
        @click="switchToWhisper"
      />
      <CallAction
        v-else-if="!monitor.open"
        icon="i-lucide-megaphone"
        :label="
          monitor.kind === 'supervisor'
            ? t('OUTSIDER_VOICE.MONITOR.TALK_TO_CUSTOMER')
            : t('OUTSIDER_VOICE.MONITOR.ASK_TO_TALK')
        "
        :disabled="!active || monitor.pending"
        data-testid="outsider-monitor-open"
        @click="requestWhisperMode('open')"
      />
      <CallAction
        v-else
        icon="i-lucide-ear"
        :label="t('OUTSIDER_VOICE.MONITOR.BACK_TO_WHISPER')"
        active
        :disabled="!active"
        data-testid="outsider-monitor-close"
        @click="requestWhisperMode('whisper')"
      />
      <CallAction
        :icon="call.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
        :label="
          call.muted
            ? t('OUTSIDER_VOICE.CALL.UNMUTE')
            : t('OUTSIDER_VOICE.CALL.MUTE')
        "
        :active="call.muted"
        :disabled="!active || listening"
        @click="toggleMute"
      />
    </div>
  </div>
</template>
