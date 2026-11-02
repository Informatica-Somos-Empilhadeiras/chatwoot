<script setup>
// OUTSIDER: o que a URA fala num bloco (Entrega 26): o texto, lido pela voz da URA, ou um áudio próprio (enviado
// do computador ou gravado aqui pelo microfone), que tem preferência sobre o texto. O áudio fica guardado na URA
// e o bloco guarda só o id dele (VoiceAPI.uploadIvrAudio).
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  modelValue: { type: Object, default: () => ({ text: '', audio_id: null }) },
  label: { type: String, required: true },
  placeholder: { type: String, default: '' },
  flowId: { type: [Number, String], required: true },
  // áudios já guardados na URA: [{ id, filename, url }]
  audios: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue', 'uploaded']);

const MAX_SIZE = 10 * 1024 * 1024;
const RECORD_TYPES = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus'];

const { t } = useI18n();

const fileInput = ref(null);
const isUploading = ref(false);
const recorder = ref(null);

const audio = computed(() =>
  props.audios.find(item => item.id === props.modelValue?.audio_id)
);

const update = changes =>
  emit('update:modelValue', {
    text: '',
    audio_id: null,
    ...props.modelValue,
    ...changes,
  });

const upload = async file => {
  if (!file) return;
  if (file.size > MAX_SIZE) {
    useAlert(t('OUTSIDER_VOICE.IVR.PROMPT.TOO_BIG'));
    return;
  }
  isUploading.value = true;
  try {
    const { data } = await VoiceAPI.uploadIvrAudio(props.flowId, file);
    emit('uploaded', data);
    update({ audio_id: data.id });
  } catch {
    useAlert(t('OUTSIDER_VOICE.IVR.PROMPT.UPLOAD_FAILED'));
  } finally {
    isUploading.value = false;
  }
};

const onFile = event => {
  upload(event.target.files?.[0]);
  event.target.value = '';
};

const stopTracks = media =>
  media.stream.getTracks().forEach(track => track.stop());

const startRecording = async () => {
  const type = RECORD_TYPES.find(item =>
    window.MediaRecorder?.isTypeSupported(item)
  );
  if (!type) {
    useAlert(t('OUTSIDER_VOICE.NOTICES.RECORDING_UNSUPPORTED'));
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const media = new MediaRecorder(stream, { mimeType: type });
    const chunks = [];
    media.ondataavailable = event => {
      if (event.data.size) chunks.push(event.data);
    };
    media.onstop = () => {
      stopTracks(media);
      const extension = type.includes('ogg') ? 'ogg' : 'webm';
      upload(
        new File(chunks, `gravacao-ura.${extension}`, {
          type: type.split(';')[0],
        })
      );
    };
    media.start();
    recorder.value = media;
  } catch {
    useAlert(t('OUTSIDER_VOICE.IVR.PROMPT.MICROPHONE'));
  }
};

const stopRecording = () => {
  recorder.value?.stop();
  recorder.value = null;
};

// saiu do bloco gravando: para o microfone sem enviar
onBeforeUnmount(() => {
  const media = recorder.value;
  if (!media) return;
  media.onstop = () => stopTracks(media);
  media.stop();
});
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-n-slate-12">{{ label }}</span>
    <textarea
      :value="modelValue?.text || ''"
      rows="3"
      maxlength="1000"
      :placeholder="placeholder || t('OUTSIDER_VOICE.IVR.PROMPT.PLACEHOLDER')"
      class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
      :disabled="!!audio"
      @input="update({ text: $event.target.value })"
    />
    <div
      v-if="audio"
      class="flex flex-col gap-1.5 p-2 rounded-lg bg-n-alpha-1"
      data-testid="ivr-prompt-audio"
    >
      <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
        <Icon icon="i-lucide-music" class="size-3.5" />
        <span class="flex-1 truncate">{{ audio.filename }}</span>
        <Button
          xs
          ghost
          ruby
          icon="i-lucide-trash-2"
          :title="t('OUTSIDER_VOICE.IVR.PROMPT.REMOVE_AUDIO')"
          @click="update({ audio_id: null })"
        />
      </span>
      <audio :src="audio.url" controls class="w-full h-8" />
    </div>
    <div class="flex flex-wrap items-center gap-1.5">
      <input
        ref="fileInput"
        type="file"
        accept="audio/*"
        class="hidden"
        @change="onFile"
      />
      <Button
        xs
        slate
        faded
        icon="i-lucide-upload"
        :label="t('OUTSIDER_VOICE.IVR.PROMPT.UPLOAD')"
        :is-loading="isUploading && !recorder"
        :disabled="!!recorder"
        @click="fileInput?.click()"
      />
      <Button
        v-if="!recorder"
        xs
        slate
        faded
        icon="i-lucide-mic"
        :label="t('OUTSIDER_VOICE.IVR.PROMPT.RECORD')"
        :disabled="isUploading"
        @click="startRecording"
      />
      <Button
        v-else
        xs
        ruby
        icon="i-lucide-square"
        :label="t('OUTSIDER_VOICE.IVR.PROMPT.STOP')"
        @click="stopRecording"
      />
      <span
        v-if="recorder"
        class="flex items-center gap-1 text-xs text-n-ruby-11"
      >
        <span class="rounded-full size-2 bg-n-ruby-9 animate-pulse" />
        {{ t('OUTSIDER_VOICE.IVR.PROMPT.RECORDING') }}
      </span>
    </div>
  </div>
</template>
