<script setup>
// OUTSIDER: preenche os dados do cliente pelo CNPJ (Entrega 19). O servidor consulta o Cadastro
// Centralizado de Contribuintes das SEFAZ e o SINTEGRA (Outsider::Crm::CompanyLookup) e devolve só os
// campos da proposta. Razão social, IE e endereço sempre trocam pelo que veio, inclusive em branco, para não
// sobrar nada da empresa consultada antes (Entrega 21). Telefone e e-mail do contato ficam, porque costumam
// valer mais que os do cadastro; só trocam quando estão vazios ou quando vieram de uma consulta anterior.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import { errorMessage } from '../../helpers';
import { lookupDocument } from './proposalHelpers';

defineProps({
  readOnly: { type: Boolean, default: false },
});

const customer = defineModel({ type: Object, required: true });

const REGISTRY_FIELDS = [
  'company',
  'document',
  'state_registration',
  'address',
  'district',
  'city',
  'state',
  'zip',
];
const CONTACT_FIELDS = ['phone', 'email'];
const ERROR_CODES = ['invalid_document', 'not_found', 'unavailable'];

const { t } = useI18n();

const isLoading = ref(false);
const notice = ref('');
// telefone e e-mail que a última consulta preencheu
const filled = ref({});

const cnpj = computed(() => lookupDocument(customer.value.document));

const merge = found => {
  const next = { ...customer.value };
  REGISTRY_FIELDS.forEach(key => {
    next[key] = found[key] || '';
  });
  CONTACT_FIELDS.forEach(key => {
    const current = next[key]?.trim();
    if (!current || current === filled.value[key]) next[key] = found[key] || '';
  });
  filled.value = Object.fromEntries(
    CONTACT_FIELDS.map(key => [key, next[key] === found[key] ? found[key] : ''])
  );
  customer.value = next;
};

const lookup = async () => {
  if (!cnpj.value || isLoading.value) return;
  isLoading.value = true;
  notice.value = '';
  try {
    const { data } = await CrmAPI.lookupCompany(cnpj.value);
    merge(data.customer);
    notice.value = data.customer.state_registration
      ? t('OUTSIDER_CRM.PROPOSALS.LOOKUP.FILLED')
      : t('OUTSIDER_CRM.PROPOSALS.LOOKUP.FILLED_WITHOUT_IE');
  } catch (error) {
    const code = error?.response?.data?.error;
    useAlert(
      ERROR_CODES.includes(code)
        ? t(`OUTSIDER_CRM.PROPOSALS.LOOKUP.ERRORS.${code.toUpperCase()}`)
        : errorMessage(t, error)
    );
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div v-if="!readOnly" class="flex flex-wrap items-center gap-2">
    <Button
      v-tooltip.top="cnpj ? '' : t('OUTSIDER_CRM.PROPOSALS.LOOKUP.NEEDS_CNPJ')"
      type="button"
      size="xs"
      variant="faded"
      color="slate"
      icon="i-lucide-search"
      :label="t('OUTSIDER_CRM.PROPOSALS.LOOKUP.BUTTON')"
      :is-loading="isLoading"
      :disabled="!cnpj || isLoading"
      @click="lookup"
    />
    <span v-if="notice" class="text-xs text-n-slate-11">{{ notice }}</span>
  </div>
</template>
