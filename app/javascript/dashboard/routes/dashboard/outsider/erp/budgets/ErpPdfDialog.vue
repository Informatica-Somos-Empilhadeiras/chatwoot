<script setup>
// OUTSIDER: um PDF do ERP na tela: o orçamento (prévia do rascunho ou o oficial), o relatório da OS e a nota fiscal do
// Nextcloud. As páginas são desenhadas pelo pdf.js (ErpPdfPages), iguais em qualquer navegador, com zoom; "Abrir no
// navegador" abre o leitor do navegador (para imprimir) e "Baixar" salva o mesmo arquivo, sem mudar nada nele.
import { ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpPdfPages from './ErpPdfPages.vue';
import { blobError, budgetErrorMessage, pdfFilename } from './budgetHelpers';

const { t } = useI18n();
const isOpen = ref(false);
const isLoading = ref(false);
const url = ref('');
const file = ref(null);
const filename = ref('');
const zoom = ref(1);
// o pdf.js não abriu: mostra no leitor do navegador
const failed = ref(false);
const ZOOMS = [0.5, 0.75, 1, 1.25, 1.5, 2];

const release = () => {
  if (url.value) URL.revokeObjectURL(url.value);
  url.value = '';
  file.value = null;
};

const changeZoom = step => {
  const next = ZOOMS[ZOOMS.indexOf(zoom.value) + step];
  if (next) zoom.value = next;
};

const close = () => {
  isOpen.value = false;
  release();
};

// budgetId do orçamento do chat ou uma função que busca o PDF (seção ERP: ErpAPI.recordPdf)
const open = async source => {
  release();
  filename.value = 'orcamento.pdf';
  zoom.value = 1;
  failed.value = false;
  isOpen.value = true;
  isLoading.value = true;
  try {
    const response =
      typeof source === 'function'
        ? await source()
        : await ErpAPI.budgetPdf(source);
    file.value = new Blob([response.data], { type: 'application/pdf' });
    url.value = URL.createObjectURL(file.value);
    filename.value = pdfFilename(response.headers, filename.value);
  } catch (error) {
    useAlert(budgetErrorMessage(t, await blobError(error)));
    close();
  } finally {
    isLoading.value = false;
  }
};

const openInBrowser = () => window.open(url.value, '_blank');

const download = () => {
  const link = document.createElement('a');
  link.href = url.value;
  link.download = filename.value;
  link.click();
};

onBeforeUnmount(release);

defineExpose({ open, isOpen });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[10000] flex flex-col bg-n-alpha-black1 backdrop-blur-[2px]"
      @keydown.esc="close"
    >
      <div
        class="flex flex-col w-full h-full max-w-5xl mx-auto overflow-hidden shadow-xl sm:my-6 sm:h-[calc(100%-3rem)] sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header
          class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
        >
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ filename }}
          </span>
          <div class="flex items-center gap-2">
            <template v-if="file && !failed">
              <Button
                size="sm"
                variant="ghost"
                color="slate"
                icon="i-lucide-zoom-out"
                :aria-label="t('OUTSIDER_ERP.BUDGET.PDF.ZOOM_OUT')"
                :disabled="zoom === ZOOMS[0]"
                @click="changeZoom(-1)"
              />
              <span
                class="w-10 text-xs text-center tabular-nums text-n-slate-11"
              >
                {{ `${Math.round(zoom * 100)}%` }}
              </span>
              <Button
                size="sm"
                variant="ghost"
                color="slate"
                icon="i-lucide-zoom-in"
                :aria-label="t('OUTSIDER_ERP.BUDGET.PDF.ZOOM_IN')"
                :disabled="zoom === ZOOMS[ZOOMS.length - 1]"
                @click="changeZoom(1)"
              />
              <Button
                size="sm"
                variant="faded"
                color="slate"
                icon="i-lucide-external-link"
                :label="t('OUTSIDER_ERP.BUDGET.PDF.OPEN')"
                @click="openInBrowser"
              />
            </template>
            <Button
              size="sm"
              icon="i-lucide-download"
              :label="t('OUTSIDER_ERP.BUDGET.PDF.DOWNLOAD')"
              :disabled="!url"
              @click="download"
            />
            <Button
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              :aria-label="t('OUTSIDER_ERP.CANCEL')"
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
            v-if="url && failed"
            :src="url"
            :title="filename"
            class="w-full h-full border-0"
          />
          <ErpPdfPages
            v-else-if="file"
            :file="file"
            :zoom="zoom"
            class="absolute inset-0"
            @failed="failed = true"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
