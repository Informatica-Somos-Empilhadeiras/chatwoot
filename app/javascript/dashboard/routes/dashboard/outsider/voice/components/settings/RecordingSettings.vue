<script setup>
// OUTSIDER: Telefonia > Configurações > Gravações (Entrega 25; ver app/services/outsider/voice/settings_extras.rb):
// o botão Gravar no telefone, a gravação automática de toda ligação com cliente e por quantos dias a gravação
// fica guardada (Outsider::Voice::RecordingCleanupJob apaga as mais antigas toda madrugada).
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  errors: { type: Array, default: () => [] },
});

const form = defineModel('form', { type: Object, required: true });

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col gap-4 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
  >
    <label class="flex items-start gap-3 cursor-pointer">
      <Switch v-model="form.recording" class="mt-0.5" />
      <span class="flex flex-col gap-0.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_VOICE.SETTINGS.RINGING.RECORDING') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_VOICE.SETTINGS.RINGING.RECORDING_HELP') }}
        </span>
      </span>
    </label>
    <label
      class="flex items-start gap-3 pt-4 border-t cursor-pointer border-n-weak"
    >
      <Switch
        v-model="form.auto_record"
        class="mt-0.5"
        data-testid="voice-auto-record"
      />
      <span class="flex flex-col gap-0.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_VOICE.SETTINGS.RECORDING.AUTO') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_VOICE.SETTINGS.RECORDING.AUTO_HELP') }}
        </span>
      </span>
    </label>
    <p
      v-if="form.auto_record"
      class="flex gap-2 px-3 py-2 mb-0 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      <span class="i-lucide-info size-4 shrink-0" />
      {{ t('OUTSIDER_VOICE.SETTINGS.RECORDING.NOTICE') }}
    </p>
    <div class="flex flex-col gap-1.5 pt-4 border-t border-n-weak">
      <Input
        v-model="form.recording_days"
        type="number"
        min="30"
        max="1825"
        class="max-w-xs"
        :label="t('OUTSIDER_VOICE.SETTINGS.RECORDING.DAYS')"
        :message-type="errors.includes('recording_days') ? 'error' : 'info'"
        data-testid="voice-recording-days"
      />
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.SETTINGS.RECORDING.DAYS_HELP') }}
      </p>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.SETTINGS.RECORDING.QUALITY') }}
      </p>
    </div>
  </div>
</template>
