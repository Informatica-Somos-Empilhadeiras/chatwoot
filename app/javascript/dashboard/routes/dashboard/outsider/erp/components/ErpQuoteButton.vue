<script setup>
// OUTSIDER: gera no ERP o orçamento de uma proposta do CRM (Outsider::Erp::QuoteCreator). Some com a integração
// ou a escrita de orçamento desligadas, ou sem o perfil de uso. Idempotente: proposta já sincronizada mostra só o
// número. Quando o contato está ligado a clientes de mais de uma unidade, pergunta em qual gerar.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { erpState } from '../erpStore';

const props = defineProps({
  proposal: { type: Object, default: null },
  // há mudanças não salvas: o orçamento usa o que está gravado, então pedimos para salvar antes
  dirty: { type: Boolean, default: false },
});

const emit = defineEmits(['synced']);

const { t } = useI18n();

const generating = ref(false);
const pickCompanies = ref([]);
const chosenCompany = ref('');

const available = computed(
  () => erpState.enabled && erpState.canCreateQuote && props.proposal?.id
);
const synced = computed(() => Boolean(props.proposal?.erp_quote_number));

const errorMessage = error => {
  const data = error?.response?.data || {};
  if (data.error === 'quote_write_disabled')
    return t('OUTSIDER_ERP.ERRORS.QUOTE_WRITE_DISABLED');
  if (error?.response?.status === 403)
    return t('OUTSIDER_ERP.ERRORS.NO_PERMISSION');
  const reason = String(data.reason || '');
  const known = {
    forma_pagto: 'FORMA_PAGTO',
    sem_cliente: 'NO_CLIENT',
    empresa_invalida: 'COMPANY_INVALID',
    sem_itens: 'NO_ITEMS',
  };
  return t(`OUTSIDER_ERP.QUOTE.ERRORS.${known[reason] || 'GENERIC'}`);
};

const generate = async company => {
  if (props.dirty) {
    useAlert(t('OUTSIDER_ERP.QUOTE.SAVE_FIRST'));
    return;
  }
  generating.value = true;
  try {
    const { data } = await ErpAPI.generateQuote({
      proposal_id: props.proposal.id,
      company: company || undefined,
    });
    pickCompanies.value = [];
    emit('synced', {
      erp_quote_number: data.number,
      erp_company: data.company,
      erp_synced_at: new Date().toISOString(),
    });
    useAlert(
      data.already
        ? t('OUTSIDER_ERP.QUOTE.ALREADY', { number: data.number })
        : t('OUTSIDER_ERP.QUOTE.DONE', { number: data.number })
    );
    if (data.skipped?.length) {
      useAlert(
        t(
          'OUTSIDER_ERP.QUOTE.SKIPPED',
          { count: data.skipped.length },
          data.skipped.length
        )
      );
    }
  } catch (error) {
    const reason = String(error?.response?.data?.reason || '');
    // "ambiguo:somosemp,somosfilial": o contato tem clientes em mais de uma unidade; pergunta qual
    if (reason.startsWith('ambiguo:')) {
      pickCompanies.value = reason
        .slice('ambiguo:'.length)
        .split(',')
        .filter(Boolean);
      chosenCompany.value = pickCompanies.value[0] || '';
    } else {
      useAlert(errorMessage(error));
    }
  } finally {
    generating.value = false;
  }
};
</script>

<template>
  <div v-if="available" class="flex flex-col gap-1.5">
    <span
      v-if="synced"
      class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-lg bg-n-teal-3 text-n-teal-11"
    >
      <Icon icon="i-lucide-receipt" class="size-3.5" />
      {{
        t('OUTSIDER_ERP.QUOTE.SYNCED', {
          number: proposal.erp_quote_number,
          company: proposal.erp_company,
        })
      }}
    </span>

    <template v-else>
      <Button
        v-if="!pickCompanies.length"
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-receipt"
        :label="t('OUTSIDER_ERP.QUOTE.GENERATE')"
        :is-loading="generating"
        @click="generate()"
      />
      <div
        v-else
        class="flex flex-wrap items-center gap-2 p-2 rounded-lg bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_ERP.QUOTE.PICK_COMPANY') }}
        </span>
        <select
          v-model="chosenCompany"
          class="!mb-0 h-8 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <option v-for="item in pickCompanies" :key="item" :value="item">
            {{ item }}
          </option>
        </select>
        <Button
          type="button"
          size="sm"
          :label="t('OUTSIDER_ERP.QUOTE.CONFIRM')"
          :is-loading="generating"
          :disabled="!chosenCompany"
          @click="generate(chosenCompany)"
        />
        <Button
          type="button"
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('OUTSIDER_ERP.CANCEL')"
          @click="pickCompanies = []"
        />
      </div>
    </template>
  </div>
</template>
