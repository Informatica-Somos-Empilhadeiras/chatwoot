<script setup>
// OUTSIDER: prévia do PDF ao lado do editor, com uma proposta de exemplo (cliente fictício, primeira
// máquina do catálogo). Usa o que está na tela, salvo ou não, e se atualiza sozinha um instante depois de
// cada alteração; nada é gravado.
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { errorMessage } from '../../../helpers';

const props = defineProps({
  templateId: { type: Number, required: true },
  payload: { type: Object, required: true },
});

const emit = defineEmits(['hide']);

const { t } = useI18n();

const url = ref('');
const isLoading = ref(false);
const failure = ref('');
let request = 0;

const release = () => {
  if (url.value) URL.revokeObjectURL(url.value);
  url.value = '';
};

// erro chega como blob: lê o JSON para mostrar o motivo
const readError = async error => {
  try {
    const data = JSON.parse(await error?.response?.data?.text?.());
    return errorMessage(t, { response: { ...error.response, data } });
  } catch {
    return errorMessage(t, error);
  }
};

const refresh = async () => {
  request += 1;
  const current = request;
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.previewProposalTemplate(
      props.templateId,
      props.payload
    );
    if (current !== request) return;
    release();
    url.value = URL.createObjectURL(
      new Blob([data], { type: 'application/pdf' })
    );
    failure.value = '';
  } catch (error) {
    if (current === request) failure.value = await readError(error);
  } finally {
    if (current === request) isLoading.value = false;
  }
};

const later = debounce(refresh, 1200);

watch(() => JSON.stringify(props.payload), later);
refresh();

onBeforeUnmount(() => {
  request += 1;
  release();
});
</script>

<template>
  <div
    class="flex flex-col overflow-hidden rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
    data-template-preview
  >
    <div
      class="flex items-center justify-between gap-2 px-3 py-2 border-b border-n-weak"
    >
      <span class="flex items-center gap-2 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.TITLE') }}
        <Spinner v-if="isLoading" class="size-3.5 text-n-slate-10" />
      </span>
      <div class="flex items-center gap-1">
        <Button
          v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.REFRESH')"
          type="button"
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-refresh-cw"
          :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.REFRESH')"
          :disabled="isLoading"
          @click="refresh"
        />
        <Button
          v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.HIDE')"
          type="button"
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.HIDE')"
          @click="emit('hide')"
        />
      </div>
    </div>
    <p
      v-if="failure"
      class="px-3 py-2 mb-0 text-xs border-b text-n-ruby-11 bg-n-ruby-2 border-n-weak"
    >
      {{ failure }}
    </p>
    <div class="relative flex-1 min-h-[32rem] bg-n-alpha-1">
      <iframe
        v-if="url"
        :src="`${url}#view=FitH&navpanes=0`"
        :title="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.TITLE')"
        class="absolute inset-0 w-full h-full border-0"
      />
      <div
        v-else-if="isLoading"
        class="absolute inset-0 flex items-center justify-center"
      >
        <Spinner class="text-n-slate-10" />
      </div>
    </div>
    <p class="px-3 py-2 mb-0 text-xs border-t text-n-slate-11 border-n-weak">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PREVIEW.HELP') }}
    </p>
  </div>
</template>
