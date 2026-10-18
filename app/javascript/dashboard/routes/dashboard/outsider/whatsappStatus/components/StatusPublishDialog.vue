<script setup>
// OUTSIDER: publicar um status de texto, foto ou vídeo, do zero ou a partir de um antigo (Editar).
import { ref, reactive, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusColorPicker from './StatusColorPicker.vue';
import StatusAudiencePicker from './StatusAudiencePicker.vue';
import {
  BACKGROUND_COLORS,
  FILE_RULES,
  FONTS,
  TEXT_MAX_LENGTH,
  appendAudience,
  colorFor,
  emptyAudience,
  errorMessage,
  fetchMedia,
  isAudienceValid,
} from '../helpers';

const props = defineProps({
  inboxId: { type: Number, required: true },
});

const emit = defineEmits(['published']);

const { t } = useI18n();

const TYPES = ['text', 'image', 'video'];

const dialogRef = ref(null);
const fileInput = ref(null);
const textInput = ref(null);
const type = ref('text');
const text = ref('');
const color = ref(BACKGROUND_COLORS[0]);
const font = ref(FONTS.DEFAULT);
const file = ref(null);
const previewUrl = ref('');
const caption = ref('');
const audience = reactive(emptyAudience());
const audienceSummary = ref(null);
const isPublishing = ref(false);
// o status antigo, quando é "Editar e publicar de novo"
const source = ref(null);
const isLoadingSource = ref(false);

const tabs = computed(() => [
  { key: 'text', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.TEXT') },
  { key: 'image', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.IMAGE') },
  { key: 'video', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.VIDEO') },
]);

const fontOptions = computed(() => [
  { value: FONTS.DEFAULT, label: t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.FONT') },
  {
    value: FONTS.SCRIPT,
    label: t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.FONT_SCRIPT'),
  },
]);

const fileRules = computed(() => FILE_RULES[type.value]);

const fileError = computed(() => {
  if (!file.value) return '';
  if (!fileRules.value.types.includes(file.value.type)) {
    return type.value === 'image'
      ? t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.IMAGE_TYPE_ERROR')
      : t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.VIDEO_TYPE_ERROR');
  }
  if (file.value.size > fileRules.value.maxSize) {
    return t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.FILE_SIZE_ERROR', {
      size: fileRules.value.maxSize / 1024 / 1024,
    });
  }
  return '';
});

const isValid = computed(() => {
  if (!isAudienceValid(audience)) return false;
  if (type.value === 'text') return text.value.trim().length > 0;
  return !!file.value && !fileError.value;
});

// o texto cresce a partir do meio do quadro, como no WhatsApp
const fitText = () => {
  const input = textInput.value;
  if (!input) return;
  input.style.height = 'auto';
  input.style.height = `${input.scrollHeight}px`;
};

const clearFile = () => {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value);
  previewUrl.value = '';
  file.value = null;
  if (fileInput.value) fileInput.value.value = '';
};

const setFile = selected => {
  clearFile();
  if (!selected) return;
  file.value = selected;
  previewUrl.value = URL.createObjectURL(selected);
};

const changeType = tab => {
  type.value = tab.key;
  clearFile();
  if (tab.key === 'text') nextTick(fitText);
};

// a foto ou o vídeo do status antigo vira o arquivo escolhido
const loadSourceMedia = async status => {
  isLoadingSource.value = true;
  try {
    const { url } = await fetchMedia(props.inboxId, status.id);
    const blob = await (await fetch(url)).blob();
    const extension = blob.type.split('/')[1].replace('jpeg', 'jpg');
    setFile(new File([blob], `status.${extension}`, { type: blob.type }));
  } catch {
    useAlert(t('OUTSIDER_WHATSAPP_STATUS.VIEWER.MEDIA_ERROR'));
  } finally {
    isLoadingSource.value = false;
  }
};

const open = async (status = null) => {
  source.value = status;
  type.value = status?.type || 'text';
  text.value = status?.type === 'text' ? status.text : '';
  // a Evolution não guarda a cor, então começa com a mesma da miniatura
  color.value = status ? colorFor(status.id) : BACKGROUND_COLORS[0];
  font.value = FONTS.DEFAULT;
  caption.value = status && status.type !== 'text' ? status.text || '' : '';
  clearFile();
  Object.assign(audience, emptyAudience());
  audienceSummary.value = null;
  dialogRef.value.open();
  nextTick(fitText);
  if (status && status.type !== 'text') loadSourceMedia(status);

  try {
    const { data } = await WhatsappStatusAPI.getAudience(props.inboxId);
    audienceSummary.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const publish = async () => {
  if (!isValid.value) return;

  const formData = new FormData();
  formData.append('inbox_id', props.inboxId);
  formData.append('type', type.value);
  if (type.value === 'text') {
    formData.append('text', text.value.trim());
    formData.append('background_color', color.value);
    formData.append('font', font.value);
  } else {
    formData.append('file', file.value);
    if (caption.value.trim()) formData.append('caption', caption.value.trim());
  }
  if (source.value) formData.append('edit_of', source.value.id);
  appendAudience(formData, audience);

  isPublishing.value = true;
  try {
    const { data } = await WhatsappStatusAPI.publish(formData);
    useAlert(
      data.pending
        ? t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.PENDING')
        : t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.SUCCESS')
    );
    dialogRef.value.close();
    emit('published');
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isPublishing.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      source
        ? t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.EDIT_TITLE')
        : t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.TITLE')
    "
    width="2xl"
    overflow-y-auto
    :confirm-button-label="t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.CONFIRM')"
    :is-loading="isPublishing"
    :disable-confirm-button="!isValid"
    @confirm="publish"
    @close="clearFile"
  >
    <div class="flex flex-col gap-5">
      <p v-if="source" class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.EDIT_NOTE') }}
      </p>
      <TabBar
        :tabs="tabs"
        :initial-active-tab="TYPES.indexOf(type)"
        @tab-changed="changeType"
      />
      <div class="grid gap-6 sm:grid-cols-2">
        <div v-if="type === 'text'" class="flex flex-col gap-3">
          <div
            class="flex items-center justify-center px-5 overflow-y-auto h-80 rounded-xl"
            :style="{ backgroundColor: color }"
            @click="textInput.focus()"
          >
            <textarea
              ref="textInput"
              v-model="text"
              rows="1"
              :maxlength="TEXT_MAX_LENGTH"
              :placeholder="
                t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.TEXT_PLACEHOLDER')
              "
              class="w-full max-h-full p-0 text-2xl font-medium text-center text-white resize-none reset-base !rounded-none !bg-transparent !border-0 !outline-0 !mb-0 placeholder:!text-white/70"
              :class="{ 'italic font-serif': font === FONTS.SCRIPT }"
              @input="fitText"
            />
          </div>
          <StatusColorPicker v-model="color" />
          <div class="flex items-center justify-between gap-3">
            <Select v-model="font" :options="fontOptions" />
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ text.length }} / {{ TEXT_MAX_LENGTH }}
            </span>
          </div>
        </div>

        <div v-else class="flex flex-col gap-3">
          <input
            ref="fileInput"
            type="file"
            class="hidden"
            :accept="fileRules.types.join(',')"
            @change="setFile($event.target.files[0])"
          />
          <div
            v-if="isLoadingSource"
            class="flex items-center justify-center h-80 rounded-xl bg-n-alpha-1"
          >
            <Spinner class="text-n-slate-10" />
          </div>
          <div
            v-else-if="!file"
            class="flex flex-col items-center justify-center gap-3 p-6 text-center border-2 border-dashed h-80 rounded-xl border-n-weak"
            @dragover.prevent
            @drop.prevent="setFile($event.dataTransfer.files[0])"
          >
            <Icon
              :icon="type === 'image' ? 'i-lucide-image' : 'i-lucide-video'"
              class="size-8 text-n-slate-10"
            />
            <p class="mb-0 text-sm text-n-slate-11">
              {{
                type === 'image'
                  ? t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.IMAGE_HINT')
                  : t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.VIDEO_HINT')
              }}
            </p>
            <Button
              type="button"
              size="sm"
              variant="faded"
              :label="t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.CHOOSE_FILE')"
              @click="fileInput.click()"
            />
          </div>
          <div
            v-else
            class="relative flex items-center justify-center overflow-hidden bg-n-black h-80 rounded-xl"
          >
            <img
              v-if="type === 'image'"
              :src="previewUrl"
              class="object-contain max-w-full max-h-full"
            />
            <video
              v-else
              :src="previewUrl"
              controls
              class="max-w-full max-h-full"
            />
            <Button
              type="button"
              icon="i-lucide-x"
              size="sm"
              color="slate"
              class="absolute top-2 ltr:right-2 rtl:left-2"
              @click="clearFile"
            />
          </div>
          <p v-if="fileError" class="mb-0 text-sm text-n-ruby-11">
            {{ fileError }}
          </p>
          <TextArea
            v-model="caption"
            :placeholder="
              t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.CAPTION_PLACEHOLDER')
            "
            :max-length="TEXT_MAX_LENGTH"
            show-character-count
            auto-height
          />
        </div>

        <StatusAudiencePicker
          v-model:mode="audience.mode"
          v-model:contact-ids="audience.contactIds"
          v-model:numbers="audience.numbers"
          id-prefix="publish"
          :inbox-id="inboxId"
          :summary="audienceSummary"
        />
      </div>
    </div>
  </Dialog>
</template>
