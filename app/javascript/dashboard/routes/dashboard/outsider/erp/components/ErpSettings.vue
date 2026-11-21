<script setup>
// OUTSIDER: Ordens de serviço > Configurações (só administradores). Ligar a integração, endereço da API do ERP, empresas
// (bancos) do grupo, x-device-id, período e cache do espelho, orçamentos e a escrita (desligada até alguém ligar).
// Campos novos de gravação só entram com o nome do endpoint lido no DevTools numa ação real feita no ERP.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpState, loadErpStatus, erpErrorMessage } from '../erpStore';

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const loading = ref(true);
const saving = ref(false);
const testing = ref(false);
const form = ref(null);
const people = ref([]);
const companiesText = ref('');
const substatusText = ref('');
const deviceId = ref('');
const nextcloudPassword = ref('');
const errors = ref([]);
const testResult = ref(null);
const loadError = ref('');
// formas de pagamento do ERP (lista para escolher a padrão do orçamento; sem lista, o campo vira número)
const paymentTerms = ref([]);
// gêneros da operação e tipos de frete (listas fixas do servidor) para os padrões do orçamento
const quoteLists = ref({});
const QUOTE_SELECTS = [
  {
    key: 'quote_tipo_frete',
    list: 'fretes',
    label: 'OUTSIDER_ERP.SETTINGS.QUOTE_TIPO_FRETE',
  },
  {
    key: 'quote_genero_operacao',
    list: 'generos',
    label: 'OUTSIDER_ERP.SETTINGS.QUOTE_GENERO',
  },
];

const INPUT =
  '!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6';

const fill = data => {
  form.value = {
    ...data.settings,
    extra_fields: (data.settings.extra_fields || []).map(row => ({ ...row })),
    user_erp_ids: { ...(data.settings.user_erp_ids || {}) },
  };
  people.value = data.people || [];
  quoteLists.value = data.quote_lists || {};
  companiesText.value = (data.settings.companies || []).join(', ');
  substatusText.value = (data.settings.substatus_options || []).join('\n');
  deviceId.value = '';
  nextcloudPassword.value = '';
};

const loadPaymentTerms = async () => {
  try {
    const { data } = await ErpAPI.paymentTerms();
    paymentTerms.value = data.payment_terms || [];
  } catch {
    paymentTerms.value = [];
  }
};

// a forma de pagamento gravada entra na lista mesmo se o ERP não a devolver
const paymentOptions = computed(() => {
  const current = Number(form.value?.quote_forma_pagto || 0);
  const list = paymentTerms.value;
  if (!current || list.some(item => item.codigo === current)) return list;
  return [{ codigo: current, descricao: '' }, ...list];
});

const load = async () => {
  loading.value = true;
  loadError.value = '';
  try {
    const { data } = await ErpAPI.settings();
    fill(data);
    if (data.settings.enabled && data.settings.companies?.length)
      loadPaymentTerms();
  } catch (error) {
    // sem isto a tela ficava em branco quando o /settings falhava (form nulo, sem v-else)
    loadError.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

onMounted(load);

const hasError = key => errors.value.includes(key);

const save = async (extra = {}) => {
  saving.value = true;
  errors.value = [];
  try {
    const { data } = await ErpAPI.saveSettings({
      ...form.value,
      companies: companiesText.value.split(/[\s,;]+/).filter(Boolean),
      substatus_options: substatusText.value.split('\n'),
      device_id: deviceId.value,
      nextcloud_password: nextcloudPassword.value,
      ...extra,
    });
    fill(data);
    await loadErpStatus(accountId.value);
    useAlert(t('OUTSIDER_ERP.SETTINGS.SAVED'));
  } catch (error) {
    errors.value = error?.response?.data?.fields || [];
    useAlert(
      errors.value.length
        ? t('OUTSIDER_ERP.SETTINGS.INVALID')
        : erpErrorMessage(t, error)
    );
  } finally {
    saving.value = false;
  }
};

// testa o que está na tela: salva antes (o teste do servidor usa a configuração gravada)
const test = async () => {
  testing.value = true;
  testResult.value = null;
  await save();
  if (errors.value.length) {
    testing.value = false;
    return;
  }
  try {
    const { data } = await ErpAPI.test();
    testResult.value = data;
  } catch (error) {
    testResult.value = { error: erpErrorMessage(t, error) };
  } finally {
    testing.value = false;
  }
};

// "SubStatus → UpdateSubStatusOS + GravaHistoricoSubStatusOS · Defeitos → UpdateDefeitos"
const confirmedText = computed(() =>
  [
    'SubStatus → UpdateSubStatusOS + GravaHistoricoSubStatusOS',
    ...Object.entries(form.value?.confirmed_fields || {}).map(
      ([field, endpoint]) => `${field} → ${endpoint}`
    ),
  ].join(' · ')
);

const addField = () =>
  form.value.extra_fields.push({ field: '', endpoint: '' });
const removeField = index => form.value.extra_fields.splice(index, 1);
</script>

<template>
  <div v-if="loading" class="flex justify-center p-8">
    <Spinner class="text-n-slate-10" />
  </div>
  <form
    v-else-if="form"
    class="flex flex-col max-w-3xl gap-8"
    @submit.prevent="save()"
  >
    <!-- conexão -->
    <section class="flex flex-col gap-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-1">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('OUTSIDER_ERP.SETTINGS.CONNECTION') }}
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('OUTSIDER_ERP.SETTINGS.CONNECTION_HINT') }}
          </p>
        </div>
        <label class="flex items-center gap-2 text-sm text-n-slate-12 shrink-0">
          <Switch v-model="form.enabled" />
          {{ t('OUTSIDER_ERP.SETTINGS.ENABLED') }}
        </label>
      </div>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.BASE_URL')
        }}</span>
        <input
          v-model="form.base_url"
          type="text"
          :class="[INPUT, hasError('base_url') && '!outline-n-ruby-9']"
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.BASE_URL_HINT')
        }}</span>
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.COMPANIES')
        }}</span>
        <input
          v-model="companiesText"
          type="text"
          :class="[INPUT, hasError('companies') && '!outline-n-ruby-9']"
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.COMPANIES_HINT')
        }}</span>
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.DEVICE_ID')
        }}</span>
        <input
          v-model="deviceId"
          type="password"
          autocomplete="off"
          :class="[INPUT, hasError('device_id') && '!outline-n-ruby-9']"
          :placeholder="
            form.device_id_set ? t('OUTSIDER_ERP.SETTINGS.DEVICE_ID_SET') : ''
          "
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.DEVICE_ID_HINT')
        }}</span>
      </label>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          type="button"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-plug-zap"
          :label="t('OUTSIDER_ERP.SETTINGS.TEST')"
          :is-loading="testing"
          @click="test"
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.TEST_HINT')
        }}</span>
      </div>
      <div
        v-if="testResult"
        class="p-3 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12"
      >
        <p v-if="testResult.error" class="mb-0 text-n-ruby-11">
          {{ testResult.error }}
        </p>
        <template v-else>
          <p class="mb-1">
            {{
              t('OUTSIDER_ERP.SETTINGS.TEST_ORDERS', {
                count: testResult.orders,
              })
            }}
            <span
              v-for="(count, company) in testResult.companies"
              :key="company"
              class="ml-2 text-n-slate-11"
            >
              {{ company }}: {{ count }}
            </span>
          </p>
          <p class="mb-0 text-n-slate-11">
            {{ t('OUTSIDER_ERP.SETTINGS.TEST_SUBSTATUS') }}
            {{ testResult.substatus.join(' · ') }}
          </p>
        </template>
      </div>
    </section>

    <!-- espelho -->
    <section class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.SETTINGS.MIRROR') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_ERP.SETTINGS.MIRROR_HINT') }}
        </p>
      </div>
      <div class="grid gap-3 sm:grid-cols-4">
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.LOOKBACK')
          }}</span>
          <input
            v-model.number="form.lookback_days"
            type="number"
            min="1"
            max="730"
            :class="INPUT"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.FORWARD')
          }}</span>
          <input
            v-model.number="form.forward_days"
            type="number"
            min="0"
            max="730"
            :class="INPUT"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.DATE_TYPE')
          }}</span>
          <select v-model="form.date_type" :class="INPUT">
            <option value="DataEntrada">
              {{ t('OUTSIDER_ERP.SETTINGS.DATE_ENTRY') }}
            </option>
            <option value="DataPrevisao">
              {{ t('OUTSIDER_ERP.SETTINGS.DATE_FORECAST') }}
            </option>
            <option value="DataEntrega">
              {{ t('OUTSIDER_ERP.SETTINGS.DATE_DELIVERY') }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.CACHE')
          }}</span>
          <input
            v-model.number="form.cache_seconds"
            type="number"
            min="30"
            max="3600"
            :class="INPUT"
          />
        </label>
      </div>
      <div class="flex flex-col gap-1">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.orders_enabled" />
          {{ t('OUTSIDER_ERP.SETTINGS.ORDERS') }}
        </label>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('OUTSIDER_ERP.SETTINGS.ORDERS_HINT') }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-4">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.quotes_enabled" />
          {{ t('OUTSIDER_ERP.SETTINGS.QUOTES') }}
        </label>
        <label class="flex items-center gap-2 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.QUOTES_DAYS')
          }}</span>
          <input
            v-model.number="form.quotes_days"
            type="number"
            min="7"
            max="730"
            :class="INPUT"
            class="!w-24"
          />
        </label>
      </div>
    </section>

    <!-- escrita -->
    <section class="flex flex-col gap-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-1">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('OUTSIDER_ERP.SETTINGS.WRITE') }}
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('OUTSIDER_ERP.SETTINGS.WRITE_HINT') }}
          </p>
        </div>
        <label class="flex items-center gap-2 text-sm text-n-slate-12 shrink-0">
          <Switch v-model="form.write_enabled" />
          {{ t('OUTSIDER_ERP.SETTINGS.WRITE_ENABLED') }}
        </label>
      </div>
      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <Switch v-model="form.note_on_change" />
        {{ t('OUTSIDER_ERP.SETTINGS.NOTE_ON_CHANGE') }}
      </label>
      <div class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.CONFIRMED')
        }}</span>
        <span class="text-xs text-n-slate-10">{{ confirmedText }}</span>
      </div>
      <div class="flex flex-col gap-2 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.EXTRA_FIELDS')
        }}</span>
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.EXTRA_FIELDS_HINT')
        }}</span>
        <div
          v-for="(row, index) in form.extra_fields"
          :key="index"
          class="flex items-center gap-2"
        >
          <input
            v-model="row.field"
            type="text"
            :class="[INPUT, hasError('extra_fields') && '!outline-n-ruby-9']"
            class="!flex-1 !w-auto"
            :placeholder="t('OUTSIDER_ERP.SETTINGS.FIELD_NAME')"
          />
          <input
            v-model="row.endpoint"
            type="text"
            :class="[INPUT, hasError('extra_fields') && '!outline-n-ruby-9']"
            class="!flex-1 !w-auto"
            :placeholder="t('OUTSIDER_ERP.SETTINGS.FIELD_ENDPOINT')"
          />
          <Button
            type="button"
            size="sm"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            :aria-label="t('OUTSIDER_ERP.SETTINGS.REMOVE')"
            @click="removeField(index)"
          />
        </div>
        <Button
          type="button"
          size="xs"
          variant="link"
          class="self-start"
          :label="t('OUTSIDER_ERP.SETTINGS.ADD_FIELD')"
          @click="addField"
        />
      </div>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.SUBSTATUS_LIST')
        }}</span>
        <textarea
          v-model="substatusText"
          rows="4"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.SUBSTATUS_HINT')
        }}</span>
      </label>
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.ERP_USER')
          }}</span>
          <input
            v-model="form.erp_user_id"
            type="text"
            :class="[INPUT, hasError('erp_user_id') && '!outline-n-ruby-9']"
          />
          <span class="text-xs text-n-slate-10">{{
            t('OUTSIDER_ERP.SETTINGS.ERP_USER_HINT')
          }}</span>
        </label>
      </div>
      <details class="text-sm">
        <summary class="cursor-pointer text-n-slate-11">
          {{ t('OUTSIDER_ERP.SETTINGS.PEOPLE') }}
        </summary>
        <div class="flex flex-col gap-2 mt-2">
          <label
            v-for="person in people"
            :key="person.id"
            class="flex items-center justify-between gap-3"
          >
            <span class="truncate text-n-slate-12">{{ person.name }}</span>
            <input
              v-model="form.user_erp_ids[String(person.id)]"
              type="text"
              :class="INPUT"
              class="!w-28"
              :placeholder="form.erp_user_id"
            />
          </label>
        </div>
      </details>
    </section>

    <!-- cadastro de cliente no ERP pela função do Mais Prático (pré-cadastro) -->
    <section class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.SETTINGS.CLIENT_WRITE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_ERP.SETTINGS.CLIENT_WRITE_HINT') }}
        </p>
      </div>
      <label class="flex items-center gap-2 text-sm text-n-slate-12 shrink-0">
        <Switch v-model="form.client_write_enabled" />
        {{ t('OUTSIDER_ERP.SETTINGS.CLIENT_WRITE_ENABLED') }}
      </label>
    </section>

    <!-- orçamento de peças e serviços: gravação no ERP, padrões do formulário, desconto e envio -->
    <section class="flex flex-col gap-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-1">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_WRITE') }}
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_WRITE_HINT') }}
          </p>
        </div>
        <label class="flex items-center gap-2 text-sm text-n-slate-12 shrink-0">
          <Switch v-model="form.quote_write_enabled" />
          {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_WRITE_ENABLED') }}
        </label>
      </div>
      <div class="grid gap-3 sm:grid-cols-3">
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.QUOTE_FORMA_PAGTO')
          }}</span>
          <select
            v-if="paymentTerms.length"
            v-model.number="form.quote_forma_pagto"
            :class="INPUT"
          >
            <option :value="0">
              {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_FORMA_PAGTO_PICK') }}
            </option>
            <option
              v-for="item in paymentOptions"
              :key="item.codigo"
              :value="item.codigo"
            >
              {{ item.codigo }} · {{ item.descricao }}
            </option>
          </select>
          <input
            v-else
            v-model.number="form.quote_forma_pagto"
            type="number"
            min="0"
            :class="INPUT"
          />
          <span class="text-xs text-n-slate-10">{{
            t('OUTSIDER_ERP.SETTINGS.QUOTE_FORMA_PAGTO_HINT')
          }}</span>
        </label>
        <label
          v-for="field in QUOTE_SELECTS"
          :key="field.key"
          class="flex flex-col gap-1 text-sm"
        >
          <span class="text-n-slate-11">{{ t(field.label) }}</span>
          <select v-model.number="form[field.key]" :class="INPUT">
            <option
              v-for="item in quoteLists[field.list] || []"
              :key="item.codigo"
              :value="item.codigo"
            >
              {{ item.codigo }} · {{ item.descricao }}
            </option>
          </select>
        </label>
      </div>
      <div class="grid gap-3 sm:grid-cols-3">
        <label
          v-for="key in ['prazo_entrega', 'validade', 'garantia']"
          :key="key"
          class="flex flex-col gap-1 text-sm"
        >
          <span class="text-n-slate-11">{{
            t(`OUTSIDER_ERP.BUDGET.TERMS.${key.toUpperCase()}`)
          }}</span>
          <input
            v-model="form[`quote_${key}`]"
            maxlength="255"
            :placeholder="t('OUTSIDER_ERP.SETTINGS.QUOTE_DEFAULT_PLACEHOLDER')"
            :class="INPUT"
          />
        </label>
      </div>
      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <Switch v-model="form.quote_services_direct" class="mt-0.5" />
        <span class="flex flex-col">
          {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_SERVICES_DIRECT') }}
          <span class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_SERVICES_DIRECT_HINT') }}
          </span>
        </span>
      </label>

      <div class="flex flex-col gap-3 p-3 rounded-lg bg-n-alpha-1">
        <label class="flex items-start gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.quote_discount_approval" class="mt-0.5" />
          <span class="flex flex-col">
            {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_DISCOUNT') }}
            <span class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_DISCOUNT_HINT') }}
            </span>
          </span>
        </label>
        <div
          v-if="form.quote_discount_approval"
          class="grid gap-3 sm:grid-cols-3"
        >
          <label
            v-for="key in ['line', 'total']"
            :key="key"
            class="flex flex-col gap-1 text-sm"
          >
            <span class="text-n-slate-11">{{
              t(`OUTSIDER_ERP.SETTINGS.QUOTE_DISCOUNT_${key.toUpperCase()}`)
            }}</span>
            <input
              v-model.number="form[`quote_discount_${key}_max`]"
              type="number"
              min="0"
              max="100"
              :class="INPUT"
            />
          </label>
        </div>
      </div>

      <div class="flex flex-col gap-1">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_SEND') }}
        </h4>
        <p class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.SETTINGS.QUOTE_PLACEHOLDERS') }}
        </p>
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.QUOTE_EMAIL_SUBJECT')
          }}</span>
          <input
            v-model="form.quote_email_subject"
            maxlength="200"
            :class="INPUT"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('OUTSIDER_ERP.SETTINGS.QUOTE_REPLY_TO')
          }}</span>
          <input
            v-model="form.quote_reply_to"
            type="email"
            :placeholder="t('OUTSIDER_ERP.SETTINGS.QUOTE_REPLY_TO_PLACEHOLDER')"
            :class="[INPUT, hasError('quote_reply_to') && '!outline-n-ruby-9']"
          />
        </label>
      </div>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.QUOTE_EMAIL_BODY')
        }}</span>
        <textarea
          v-model="form.quote_email_body"
          rows="6"
          maxlength="4000"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.QUOTE_WHATSAPP_TEXT')
        }}</span>
        <textarea
          v-model="form.quote_whatsapp_text"
          rows="3"
          maxlength="2000"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
      </label>

      <div class="flex flex-col gap-1 pt-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.SETTINGS.OS_SEND') }}
        </h4>
        <p class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.SETTINGS.OS_PLACEHOLDERS') }}
        </p>
      </div>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.OS_EMAIL_SUBJECT')
        }}</span>
        <input v-model="form.os_email_subject" maxlength="200" :class="INPUT" />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.OS_EMAIL_BODY')
        }}</span>
        <textarea
          v-model="form.os_email_body"
          rows="6"
          maxlength="4000"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.OS_WHATSAPP_TEXT')
        }}</span>
        <textarea
          v-model="form.os_whatsapp_text"
          rows="3"
          maxlength="2000"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
      </label>

      <div class="flex flex-col gap-1 pt-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.SETTINGS.NF_SEND') }}
        </h4>
        <p class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.SETTINGS.NF_PLACEHOLDERS') }}
        </p>
      </div>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NF_EMAIL_SUBJECT')
        }}</span>
        <input v-model="form.nf_email_subject" maxlength="200" :class="INPUT" />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NF_EMAIL_BODY')
        }}</span>
        <textarea
          v-model="form.nf_email_body"
          rows="6"
          maxlength="4000"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NF_WHATSAPP_TEXT')
        }}</span>
        <textarea
          v-model="form.nf_whatsapp_text"
          rows="3"
          maxlength="2000"
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        />
      </label>

      <div class="flex flex-col gap-1 pt-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD') }}
        </h4>
        <p class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_HINT') }}
        </p>
        <p
          class="mb-0 text-xs font-medium"
          :class="
            erpState.nextcloudInvoices ? 'text-n-teal-11' : 'text-n-amber-11'
          "
        >
          {{
            erpState.nextcloudInvoices
              ? t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_ON')
              : t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_OFF')
          }}
        </p>
      </div>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_URL')
        }}</span>
        <input
          v-model="form.nextcloud_url"
          type="url"
          :placeholder="t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_URL_PLACEHOLDER')"
          :class="[INPUT, hasError('nextcloud_url') && '!outline-n-ruby-9']"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_USER')
        }}</span>
        <input
          v-model="form.nextcloud_user"
          autocomplete="off"
          :class="[INPUT, hasError('nextcloud_user') && '!outline-n-ruby-9']"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_PASSWORD')
        }}</span>
        <input
          v-model="nextcloudPassword"
          type="password"
          autocomplete="new-password"
          :class="INPUT"
          :placeholder="
            form.nextcloud_password_set
              ? t('OUTSIDER_ERP.SETTINGS.DEVICE_ID_SET')
              : ''
          "
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_PASSWORD_HINT')
        }}</span>
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_FOLDER')
        }}</span>
        <input
          v-model="form.nextcloud_folder"
          :placeholder="t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_FOLDER_PLACEHOLDER')"
          :class="[INPUT, hasError('nextcloud_folder') && '!outline-n-ruby-9']"
        />
        <span class="text-xs text-n-slate-10">{{
          t('OUTSIDER_ERP.SETTINGS.NEXTCLOUD_FOLDER_HINT')
        }}</span>
      </label>
    </section>

    <div class="flex justify-end">
      <Button
        type="submit"
        :label="t('OUTSIDER_ERP.SETTINGS.SAVE')"
        :is-loading="saving"
      />
    </div>
  </form>
  <div
    v-else
    class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
  >
    <Icon icon="i-lucide-triangle-alert" class="size-8 text-n-ruby-9" />
    <p class="max-w-md mb-0 text-sm text-n-slate-11">{{ loadError }}</p>
    <Button
      type="button"
      size="sm"
      variant="faded"
      color="slate"
      icon="i-lucide-refresh-cw"
      :label="t('OUTSIDER_ERP.SETTINGS.RELOAD')"
      @click="load"
    />
  </div>
</template>
