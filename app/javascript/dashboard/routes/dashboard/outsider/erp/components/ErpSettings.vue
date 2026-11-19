<script setup>
// OUTSIDER: Ordens de serviço > Configurações (só administradores). Ligar a integração, endereço da API do ERP, empresas
// (bancos) do grupo, x-device-id, período e cache do espelho, orçamentos e a escrita (desligada até alguém ligar).
// Campos novos de gravação só entram com o nome do endpoint lido no DevTools numa ação real feita no ERP.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { loadErpStatus, erpErrorMessage } from '../erpStore';

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
const errors = ref([]);
const testResult = ref(null);

const INPUT =
  '!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak';

const fill = data => {
  form.value = {
    ...data.settings,
    extra_fields: (data.settings.extra_fields || []).map(row => ({ ...row })),
    user_erp_ids: { ...(data.settings.user_erp_ids || {}) },
  };
  people.value = data.people || [];
  companiesText.value = (data.settings.companies || []).join(', ');
  substatusText.value = (data.settings.substatus_options || []).join('\n');
  deviceId.value = '';
};

onMounted(async () => {
  try {
    const { data } = await ErpAPI.settings();
    fill(data);
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    loading.value = false;
  }
});

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

const test = async () => {
  testing.value = true;
  testResult.value = null;
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
          class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
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

    <div class="flex justify-end">
      <Button
        type="submit"
        :label="t('OUTSIDER_ERP.SETTINGS.SAVE')"
        :is-loading="saving"
      />
    </div>
  </form>
</template>
