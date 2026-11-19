<script setup>
// OUTSIDER: orçamentos do ERP dos clientes ligados ao contato (cotacaoDesempenho). Na primeira vez a cópia é montada no
// Sidekiq (uma chamada por empresa) e a tela tenta de novo sozinha por alguns segundos.
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  formatDate,
  formatMoney,
  quoteClass,
  withLoadingRetry,
  erpErrorMessage,
} from '../erpStore';

const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const loading = ref(false);
const failure = ref('');
const quotes = ref([]);

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await withLoadingRetry(
      () => ErpAPI.quotes(props.contactId),
      { tries: 10, wait: 3000 }
    );
    quotes.value = data.quotes || [];
  } catch (error) {
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, load, { immediate: true });

const openTotal = computed(() =>
  quotes.value
    .filter(quote => String(quote.Status).toUpperCase().includes('NEGOC'))
    .reduce((sum, quote) => sum + Number(quote.ValorTotal || 0), 0)
);
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-if="loading"
      class="flex items-center gap-2 p-2 text-xs text-n-slate-10"
    >
      <Spinner class="size-4" />
      {{ t('OUTSIDER_ERP.QUOTES.LOADING') }}
    </div>
    <p v-else-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
      <button type="button" class="underline" @click="load">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>
    <template v-else>
      <p v-if="!quotes.length" class="mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.QUOTES.EMPTY') }}
      </p>
      <p v-else-if="openTotal" class="mb-0 text-xs text-n-slate-11">
        {{
          t('OUTSIDER_ERP.QUOTES.OPEN_TOTAL', { value: formatMoney(openTotal) })
        }}
      </p>
      <article
        v-for="quote in quotes"
        :key="`${quote.Banco}:${quote.CodigoOrcamento}`"
        class="flex flex-col gap-1 p-3 text-sm border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_ERP.QUOTES.CODE', { code: quote.CodigoOrcamento }) }}
            <span class="text-xs font-normal text-n-slate-10">{{
              quote.Banco
            }}</span>
          </span>
          <span
            class="px-2 py-0.5 text-xs rounded-full"
            :class="quoteClass(quote.Status)"
          >
            {{ quote.Status }}
          </span>
        </div>
        <span class="font-medium text-n-slate-12">{{
          formatMoney(quote.ValorTotal)
        }}</span>
        <span class="flex flex-wrap text-xs gap-x-3 gap-y-1 text-n-slate-11">
          <span>{{ formatDate(quote.DataCadastro) }}</span>
          <span v-if="quote.Vendedor">{{ quote.Vendedor }}</span>
          <span v-if="quote.OrdemServico">
            {{ t('OUTSIDER_ERP.ORDER.CODE', { code: quote.OrdemServico }) }}
          </span>
          <span v-if="quote.Pedido">
            {{ t('OUTSIDER_ERP.QUOTES.ORDER', { code: quote.Pedido }) }}
          </span>
          <span v-if="quote.AlertaFollow">{{ quote.AlertaFollow }}</span>
        </span>
      </article>
    </template>
  </div>
</template>
