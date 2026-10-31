<script setup>
// OUTSIDER: painel do bloco Enviar arquivo: o arquivo (PDF, imagem, catálogo...) é enviado aqui mesmo e fica
// guardado no fluxo uma vez; o bloco guarda só a referência e cada envio ao cliente usa o mesmo arquivo.
import { computed, inject, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BotFlowsAPI from 'dashboard/api/outsider/botFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TemplateField from './TemplateField.vue';
import { braces } from './template';
import {
  FILE_EXTENSIONS,
  MAX_FILE_BYTES,
  fileExtension,
  fileIcon,
  formatBytes,
} from './integrationTypes';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const flowId = inject('botFlowId', ref(null));
const flowFiles = inject('botFiles', ref([]));
const pendingFiles = inject('botPendingFiles', {});
const data = computed(() => props.node.data);

const input = ref(null);
const uploading = ref(false);
const progress = ref(0);
const error = ref('');
const dragging = ref(false);

const stored = computed(() =>
  flowFiles.value.find(item => item.blob_id === data.value.file?.blob_id)
);
const isImage = computed(() =>
  String(data.value.file?.content_type || '').startsWith('image/')
);

const upload = async file => {
  error.value = '';
  if (!FILE_EXTENSIONS.includes(fileExtension(file.name))) {
    error.value = t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.ERRORS.file_type', {
      types: FILE_EXTENSIONS.join(', '),
    });
    return;
  }
  if (file.size > MAX_FILE_BYTES) {
    error.value = t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.ERRORS.file_too_big');
    return;
  }
  uploading.value = true;
  progress.value = 0;
  try {
    const { data: saved } = await BotFlowsAPI.uploadFile(
      flowId.value,
      file,
      event => {
        if (event.total) {
          progress.value = Math.round((event.loaded / event.total) * 100);
        }
      }
    );
    flowFiles.value = [
      ...flowFiles.value.filter(item => item.blob_id !== saved.blob_id),
      saved,
    ];
    data.value.file = {
      blob_id: saved.blob_id,
      name: saved.name,
      size: saved.size,
      content_type: saved.content_type,
    };
  } catch (failure) {
    const code = failure?.response?.data?.error;
    error.value = t(
      `OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.ERRORS.${code || 'upload_failed'}`,
      { types: FILE_EXTENSIONS.join(', ') }
    );
  } finally {
    uploading.value = false;
  }
};

const pick = () => input.value?.click();
const onPick = event => {
  const [file] = event.target.files || [];
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
  if (file) upload(file);
};
const onDrop = event => {
  dragging.value = false;
  const [file] = event.dataTransfer?.files || [];
  if (file) upload(file);
};
const removeFile = () => {
  data.value.file = null;
  error.value = '';
};

// arquivo solto no quadro: o bloco foi criado para ele
const takePending = () => {
  const file = pendingFiles[props.node.id];
  if (!file) return;
  delete pendingFiles[props.node.id];
  upload(file);
};
onMounted(takePending);
watch(() => props.node.id, takePending);
</script>

<template>
  <div class="flex flex-col gap-4">
    <input
      ref="input"
      type="file"
      class="hidden"
      :accept="FILE_EXTENSIONS.map(extension => `.${extension}`).join(',')"
      @change="onPick"
    />

    <div
      v-if="data.file && !uploading"
      class="flex flex-col gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-2"
    >
      <div class="flex items-center gap-3">
        <img
          v-if="isImage && stored"
          :src="stored.url"
          alt=""
          class="object-cover rounded-lg size-12 shrink-0 bg-n-alpha-2"
        />
        <span
          v-else
          class="flex items-center justify-center rounded-lg size-12 shrink-0 bg-n-iris-3 text-n-iris-11"
        >
          <Icon
            :icon="fileIcon(data.file.content_type, data.file.name)"
            class="size-6"
          />
        </span>
        <div class="flex flex-col min-w-0 gap-0.5">
          <span
            class="text-sm font-medium break-all line-clamp-2 text-n-slate-12"
            :title="data.file.name"
          >
            {{ data.file.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ formatBytes(data.file.size) }} ·
            {{ fileExtension(data.file.name).toUpperCase() }}
          </span>
        </div>
      </div>
      <p
        v-if="!stored"
        class="flex items-start gap-1.5 mb-0 text-xs text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 shrink-0" />
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.GONE') }}
      </p>
      <div class="flex flex-wrap items-center gap-1.5">
        <a
          v-if="stored"
          :href="stored.url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 h-7 px-2.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
        >
          <Icon icon="i-lucide-external-link" class="size-3.5" />
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.OPEN') }}
        </a>
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.REPLACE')"
          icon="i-lucide-refresh-cw"
          xs
          faded
          slate
          @click="pick"
        />
        <Button
          v-tooltip.top="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.REMOVE')"
          icon="i-lucide-trash-2"
          xs
          ghost
          ruby
          class="ltr:ml-auto rtl:mr-auto"
          @click="removeFile"
        />
      </div>
    </div>

    <button
      v-else
      type="button"
      class="flex flex-col items-center gap-2 px-4 py-6 text-center border-2 border-dashed rounded-xl transition-colors"
      :class="
        dragging
          ? 'border-n-brand bg-n-brand/5'
          : 'border-n-weak hover:border-n-slate-8'
      "
      :disabled="uploading"
      @click="pick"
      @dragover.prevent="dragging = true"
      @dragleave="dragging = false"
      @drop.prevent="onDrop"
    >
      <span
        class="flex items-center justify-center rounded-xl size-11 bg-n-iris-3 text-n-iris-11"
      >
        <Icon icon="i-lucide-upload" class="size-5" />
      </span>
      <span class="text-sm font-medium text-n-slate-12">
        {{
          uploading
            ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.UPLOADING', {
                progress,
              })
            : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.DROP')
        }}
      </span>
      <div
        v-if="uploading"
        class="w-full h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
      >
        <div
          class="h-full transition-all rounded-full bg-n-iris-9"
          :style="{ width: `${progress}%` }"
        />
      </div>
      <span v-else class="text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.DROP_HINT') }}
      </span>
    </button>

    <p
      v-if="error"
      class="flex items-start gap-1.5 mb-0 text-sm text-n-ruby-11"
    >
      <Icon icon="i-lucide-circle-x" class="size-4 mt-0.5 shrink-0" />
      {{ error }}
    </p>

    <TemplateField
      v-model="data.caption"
      multiline
      :rows="2"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.CAPTION')"
      :placeholder="
        t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.CAPTION_PLACEHOLDER', {
          name: braces('contato.primeiro_nome'),
        })
      "
      :hint="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.CAPTION_HINT')"
      :maxlength="1000"
    />
    <p class="flex items-start gap-2 mb-0 text-xs text-n-slate-10">
      <Icon icon="i-lucide-info" class="size-4 shrink-0" />
      {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FILE.STORED_HINT') }}
    </p>
  </div>
</template>
