<script setup>
// OUTSIDER: mostra o PDF da proposta dentro do CRM. O servidor monta o PDF na hora (nada é gravado
// para visualizar); "Baixar" salva o mesmo arquivo no computador.
import { ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { errorMessage } from '../../helpers';
import { pdfFilename } from './proposalHelpers';

const { t } = useI18n();

const isOpen = ref(false);
const isLoading = ref(false);
const url = ref('');
const filename = ref('');
const title = ref('');

const release = () => {
  if (url.value) URL.revokeObjectURL(url.value);
  url.value = '';
};

const close = () => {
  isOpen.value = false;
  release();
};

const open = async proposal => {
  release();
  title.value = proposal.code || '';
  filename.value = `${proposal.code || 'proposta'}.pdf`;
  isOpen.value = true;
  isLoading.value = true;
  try {
    const response = await CrmAPI.getProposalPdf(proposal.id);
    url.value = URL.createObjectURL(
      new Blob([response.data], { type: 'application/pdf' })
    );
    filename.value = pdfFilename(response.headers, filename.value);
  } catch (error) {
    // resposta de erro chega como blob: lê o JSON para mostrar o motivo
    let data = null;
    try {
      data = JSON.parse(await error?.response?.data?.text?.());
    } catch {
      data = null;
    }
    useAlert(
      errorMessage(t, data ? { response: { ...error.response, data } } : error)
    );
    close();
  } finally {
    isLoading.value = false;
  }
};

const download = () => {
  const link = document.createElement('a');
  link.href = url.value;
  link.download = filename.value;
  link.click();
};

const onKeydown = event => {
  if (event.key === 'Escape') close();
};

onBeforeUnmount(release);

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[9999] flex flex-col bg-n-alpha-black1 backdrop-blur-[2px]"
      tabindex="-1"
      @keydown="onKeydown"
    >
      <div
        class="flex flex-col w-full h-full max-w-5xl mx-auto my-0 overflow-hidden shadow-xl sm:my-6 sm:h-[calc(100%-3rem)] sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header
          class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
        >
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ t('OUTSIDER_CRM.PROPOSALS.PDF.TITLE', { code: title }) }}
          </span>
          <div class="flex items-center gap-2">
            <Button
              size="sm"
              icon="i-lucide-download"
              :label="t('OUTSIDER_CRM.PROPOSALS.PDF.DOWNLOAD')"
              :disabled="!url"
              @click="download"
            />
            <Button
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              :aria-label="t('OUTSIDER_CRM.CANCEL')"
              @click="close"
            />
          </div>
        </header>
        <div class="relative flex-1 bg-n-alpha-1">
          <div
            v-if="isLoading"
            class="absolute inset-0 flex items-center justify-center"
          >
            <Spinner class="text-n-slate-10" />
          </div>
          <iframe
            v-if="url"
            :src="url"
            :title="title"
            class="w-full h-full border-0"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
