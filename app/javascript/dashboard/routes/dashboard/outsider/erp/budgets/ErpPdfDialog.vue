<script setup>
// OUTSIDER: PDF do orçamento de peças e serviços na tela (prévia do rascunho ou o oficial do ERP), montado na hora pelo
// servidor no modelo do relatório do Mais Prático. "Baixar" salva o mesmo arquivo.
import { ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { blobError, budgetErrorMessage, pdfFilename } from './budgetHelpers';

const { t } = useI18n();
const isOpen = ref(false);
const isLoading = ref(false);
const url = ref('');
const filename = ref('');

const release = () => {
  if (url.value) URL.revokeObjectURL(url.value);
  url.value = '';
};

const close = () => {
  isOpen.value = false;
  release();
};

// budgetId do orçamento do chat ou uma função que busca o PDF (seção ERP: ErpAPI.recordPdf)
const open = async source => {
  release();
  filename.value = 'orcamento.pdf';
  isOpen.value = true;
  isLoading.value = true;
  try {
    const response =
      typeof source === 'function'
        ? await source()
        : await ErpAPI.budgetPdf(source);
    url.value = URL.createObjectURL(
      new Blob([response.data], { type: 'application/pdf' })
    );
    filename.value = pdfFilename(response.headers, filename.value);
  } catch (error) {
    useAlert(budgetErrorMessage(t, await blobError(error)));
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
            v-if="url"
            :src="url"
            :title="filename"
            class="w-full h-full border-0"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
