<script setup>
// OUTSIDER: "Cadastrar cliente no ERP". O cliente entra no Mais Prático pela função do próprio ERP, como pré-cadastro
// (o escritório completa município, perfil e o resto). Abre da seção ERP, do bloco do ERP no contato e da escolha de
// cliente do orçamento; com um contato, já vem com o nome, a empresa e o telefone dele, e o contato fica vinculado ao
// cliente novo. CPF/CNPJ já cadastrado na unidade: avisa e oferece usar o existente em vez de gravar outro. CNPJ novo:
// busca os dados da empresa (a mesma consulta das propostas) e preenche o cadastro (mergeCompany).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpState, erpErrorMessage, companyName } from '../erpStore';
import {
  UFS,
  EMPTY_CLIENT,
  fromContact,
  cleanDocument,
  isValidDocument,
  maskDocument,
  maskCep,
  mergeCompany,
} from './clientHelpers';

const emit = defineEmits(['created']);

const { t } = useI18n();
const store = useStore();

const isOpen = ref(false);
const saving = ref(false);
const company = ref('');
const contactId = ref(null);
const form = ref(EMPTY_CLIENT());
const sellers = ref([]);
const existing = ref(null);
const checking = ref(false);
const touched = ref(false);
const serverFields = ref([]);
// consulta do CNPJ: '' | searching | filled | filled_without_ie | not_found | unavailable
const companyState = ref('');
const companyFilled = ref({});

const companies = computed(() => erpState.companies || []);
const isCompany = computed(() => form.value.person === 'J');
const documentClean = computed(() => cleanDocument(form.value.documento));
const documentDone = computed(
  () => documentClean.value.length === (isCompany.value ? 14 : 11)
);
const documentValid = computed(() => isValidDocument(form.value.documento));
const emailValid = value =>
  !value || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value).trim());

const errors = computed(() => {
  const list = new Set(serverFields.value);
  if (!documentValid.value) list.add('documento');
  if (String(form.value.nome).trim().length < 3) list.add('nome');
  if (!emailValid(form.value.email)) list.add('email');
  if (!emailValid(form.value.contato_email)) list.add('contato_email');
  const cep = String(form.value.cep).replace(/\D/g, '');
  if (cep && cep.length !== 8) list.add('cep');
  return list;
});
const showError = field => touched.value && errors.value.has(field);
const canSave = computed(
  () => !saving.value && !existing.value && errors.value.size === 0
);

const loadOptions = async () => {
  sellers.value = [];
  if (!company.value) return;
  try {
    const { data } = await ErpAPI.clientOptions(company.value);
    sellers.value = data.sellers || [];
    if (!form.value.vendedor && data.seller) form.value.vendedor = data.seller;
  } catch {
    // sem a lista: o vendedor fica em branco (o escritório completa)
  }
};

// CNPJ que ainda não é cliente da unidade: preenche com os dados da empresa (se trocar o CNPJ no meio, descarta)
const fetchCompany = async () => {
  const documento = documentClean.value;
  companyState.value = 'searching';
  try {
    const { data } = await ErpAPI.clientCompany(documento);
    if (documento !== documentClean.value) return;
    const merged = mergeCompany(form.value, data.customer, companyFilled.value);
    form.value = merged.form;
    companyFilled.value = merged.filled;
    companyState.value = data.customer.state_registration
      ? 'filled'
      : 'filled_without_ie';
  } catch (error) {
    if (documento !== documentClean.value) return;
    companyState.value =
      error?.response?.data?.error === 'not_found'
        ? 'not_found'
        : 'unavailable';
  }
};

const lookup = debounce(async () => {
  if (!documentValid.value || !company.value) return;
  checking.value = true;
  try {
    const { data } = await ErpAPI.clientLookup(
      company.value,
      documentClean.value
    );
    if (documentValid.value) existing.value = data.customer || null;
  } catch {
    existing.value = null;
  } finally {
    checking.value = false;
  }
  if (!existing.value && isCompany.value && documentValid.value) fetchCompany();
}, 400);

watch([documentClean, company], () => {
  existing.value = null;
  companyState.value = '';
  serverFields.value = serverFields.value.filter(
    field => field !== 'documento'
  );
  if (documentDone.value) lookup();
});
watch(company, loadOptions);

// CNPJ tem 14 caracteres e CPF 11: colar um documento já troca a pessoa
const onDocument = event => {
  const clean = cleanDocument(event.target.value);
  if (clean.length > 11 && !isCompany.value) form.value.person = 'J';
  form.value.documento = maskDocument(clean, form.value.person);
  event.target.value = form.value.documento;
};
const setPerson = person => {
  form.value.person = person;
  form.value.documento = maskDocument(form.value.documento, person);
};
const onCep = event => {
  form.value.cep = maskCep(event.target.value);
  event.target.value = form.value.cep;
};

// options: { company, contactId, onCreated }
let onCreated = null;
const open = (options = {}) => {
  const contact = options.contactId
    ? store.getters['contacts/getContact'](options.contactId)
    : null;
  form.value = fromContact(contact?.id ? contact : null);
  contactId.value = options.contactId || null;
  company.value = companies.value.includes(options.company)
    ? options.company
    : companies.value[0] || '';
  onCreated = options.onCreated || null;
  existing.value = null;
  touched.value = false;
  serverFields.value = [];
  companyState.value = '';
  companyFilled.value = {};
  isOpen.value = true;
  loadOptions();
};

const close = () => {
  if (saving.value) return;
  isOpen.value = false;
};

const finish = customer => {
  emit('created', customer);
  if (onCreated) onCreated(customer);
  isOpen.value = false;
};

const reasonText = data => {
  const reason = data?.reason;
  if (reason === 'dados' || reason === 'tamanho')
    return t('OUTSIDER_ERP.CLIENT.ERRORS.FIELDS');
  const known = ['empresa', 'em_andamento', 'documento', 'sem_codigo'];
  if (known.includes(reason))
    return t(`OUTSIDER_ERP.CLIENT.ERRORS.${reason.toUpperCase()}`);
  return '';
};

const save = async () => {
  touched.value = true;
  if (!canSave.value) return;
  saving.value = true;
  serverFields.value = [];
  try {
    // a pessoa (F/J) o servidor tira do tamanho do CPF/CNPJ
    const { data } = await ErpAPI.createClient(
      {
        ...form.value,
        company: company.value,
        documento: documentClean.value,
      },
      contactId.value
    );
    const customer = data.customer;
    useAlert(
      t(
        customer.existente
          ? 'OUTSIDER_ERP.CLIENT.ALREADY_DONE'
          : 'OUTSIDER_ERP.CLIENT.DONE',
        { code: customer.codigo, company: companyName(customer.empresa) }
      )
    );
    saving.value = false;
    finish(customer);
  } catch (error) {
    const data = error?.response?.data;
    serverFields.value = data?.fields || [];
    useAlert(reasonText(data) || erpErrorMessage(t, error));
  } finally {
    saving.value = false;
  }
};

// já existe: vincula o contato (se houver) e devolve o existente para quem abriu
const useExisting = async () => {
  const customer = { ...existing.value, existente: true };
  if (contactId.value) {
    try {
      await ErpAPI.link({
        contact_id: contactId.value,
        company: customer.empresa,
        code: customer.codigo,
        name: customer.nome,
      });
    } catch (error) {
      useAlert(erpErrorMessage(t, error));
      return;
    }
  }
  finish(customer);
};

const CEP_MASK = '00000-000';
const INPUT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
const SELECT = `${INPUT} !pr-7 bg-[right_-1.25rem_center]`;
const LABEL = 'flex flex-col gap-1 text-xs font-medium text-n-slate-11';
const BAD = '!outline-n-ruby-8';

defineExpose({ open, isOpen });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[10000] flex items-start justify-center p-0 sm:p-6 bg-n-alpha-black1 backdrop-blur-[2px]"
      @keydown.esc="close"
      @click.self="close"
    >
      <form
        class="flex flex-col w-full h-full max-w-3xl overflow-hidden shadow-xl sm:h-auto sm:max-h-full sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
        @submit.prevent="save"
      >
        <header
          class="flex items-start justify-between gap-3 px-5 py-4 border-b shrink-0 border-n-weak"
        >
          <div class="flex items-start gap-3 min-w-0">
            <span
              class="flex items-center justify-center rounded-lg shrink-0 size-9 bg-n-teal-3 text-n-teal-11"
            >
              <Icon icon="i-lucide-user-plus" class="size-5" />
            </span>
            <div class="flex flex-col min-w-0 gap-0.5">
              <h3 class="mb-0 text-base font-medium text-n-slate-12">
                {{ t('OUTSIDER_ERP.CLIENT.TITLE') }}
              </h3>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('OUTSIDER_ERP.CLIENT.HINT') }}
              </p>
            </div>
          </div>
          <Button
            type="button"
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('OUTSIDER_ERP.CANCEL')"
            @click="close"
          />
        </header>

        <div
          class="flex flex-col flex-1 min-h-0 gap-5 px-5 py-4 overflow-y-auto"
        >
          <div class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
            <label v-if="companies.length > 1" :class="LABEL">
              {{ t('OUTSIDER_ERP.CLIENT.UNIT') }}
              <select v-model="company" :class="SELECT">
                <option v-for="item in companies" :key="item" :value="item">
                  {{ companyName(item) }}
                </option>
              </select>
            </label>
            <div :class="LABEL" class="sm:col-start-2">
              {{ t('OUTSIDER_ERP.CLIENT.PERSON') }}
              <div class="flex items-center h-9 p-0.5 rounded-lg bg-n-alpha-2">
                <button
                  v-for="person in ['J', 'F']"
                  :key="person"
                  type="button"
                  class="h-8 px-3 text-xs rounded-md whitespace-nowrap"
                  :class="
                    form.person === person
                      ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                      : 'text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="setPerson(person)"
                >
                  {{
                    t(
                      `OUTSIDER_ERP.CLIENT.${person === 'J' ? 'COMPANY' : 'INDIVIDUAL'}`
                    )
                  }}
                </button>
              </div>
            </div>
          </div>

          <section class="grid gap-3 sm:grid-cols-6">
            <label :class="LABEL" class="sm:col-span-2">
              {{
                isCompany
                  ? t('OUTSIDER_ERP.CLIENT.CNPJ')
                  : t('OUTSIDER_ERP.CLIENT.CPF')
              }}
              <div class="relative">
                <input
                  :value="form.documento"
                  :class="[INPUT, showError('documento') && BAD]"
                  inputmode="text"
                  autocomplete="off"
                  :placeholder="
                    isCompany ? '00.000.000/0000-00' : '000.000.000-00'
                  "
                  @input="onDocument"
                />
                <Spinner
                  v-if="checking"
                  class="absolute -translate-y-1/2 right-2 top-1/2 size-3.5 text-n-slate-10"
                />
              </div>
              <span
                v-if="documentDone && !documentValid"
                class="text-[11px] font-normal text-n-ruby-11"
              >
                {{ t('OUTSIDER_ERP.CLIENT.BAD_DOCUMENT') }}
              </span>
              <span
                v-else-if="companyState"
                class="flex items-center gap-1 text-[11px] font-normal text-n-slate-11"
              >
                <Spinner
                  v-if="companyState === 'searching'"
                  class="size-3 shrink-0"
                />
                {{
                  t(`OUTSIDER_ERP.CLIENT.COMPANY.${companyState.toUpperCase()}`)
                }}
              </span>
            </label>
            <label :class="LABEL" class="sm:col-span-4">
              {{
                isCompany
                  ? t('OUTSIDER_ERP.CLIENT.LEGAL_NAME')
                  : t('OUTSIDER_ERP.CLIENT.NAME')
              }}
              <input
                v-model="form.nome"
                maxlength="100"
                :class="[INPUT, showError('nome') && BAD]"
              />
            </label>

            <div
              v-if="existing"
              class="flex flex-wrap items-center gap-3 p-3 text-sm rounded-lg sm:col-span-6 bg-n-amber-2 text-n-amber-11"
            >
              <Icon icon="i-lucide-circle-alert" class="size-4 shrink-0" />
              <span class="flex-1 min-w-[12rem]">
                {{
                  t('OUTSIDER_ERP.CLIENT.EXISTS', {
                    code: existing.codigo,
                    name: existing.nome,
                    company: companyName(existing.empresa),
                  })
                }}
              </span>
              <Button
                type="button"
                size="sm"
                color="amber"
                :label="t('OUTSIDER_ERP.CLIENT.USE_EXISTING')"
                @click="useExisting"
              />
            </div>

            <label :class="LABEL" class="sm:col-span-3">
              {{
                isCompany
                  ? t('OUTSIDER_ERP.CLIENT.TRADE_NAME')
                  : t('OUTSIDER_ERP.CLIENT.NICKNAME')
              }}
              <input v-model="form.apelido" maxlength="60" :class="INPUT" />
            </label>
            <label :class="LABEL" class="sm:col-span-3">
              {{
                isCompany
                  ? t('OUTSIDER_ERP.CLIENT.IE')
                  : t('OUTSIDER_ERP.CLIENT.RG')
              }}
              <input v-model="form.rg_ie" maxlength="20" :class="INPUT" />
            </label>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.PHONE') }}
              <input
                v-model="form.telefone"
                maxlength="20"
                inputmode="tel"
                :class="INPUT"
              />
            </label>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.MOBILE') }}
              <input
                v-model="form.celular"
                maxlength="20"
                inputmode="tel"
                :class="INPUT"
              />
            </label>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.EMAIL') }}
              <input
                v-model="form.email"
                maxlength="100"
                type="email"
                :class="[INPUT, showError('email') && BAD]"
              />
            </label>
          </section>

          <section class="flex flex-col gap-3">
            <h4 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_ERP.CLIENT.ADDRESS') }}
            </h4>
            <div class="grid gap-3 sm:grid-cols-6">
              <label :class="LABEL" class="sm:col-span-1">
                {{ t('OUTSIDER_ERP.CLIENT.CEP') }}
                <input
                  :value="form.cep"
                  inputmode="numeric"
                  :placeholder="CEP_MASK"
                  :class="[INPUT, showError('cep') && BAD]"
                  @input="onCep"
                />
              </label>
              <label :class="LABEL" class="sm:col-span-4">
                {{ t('OUTSIDER_ERP.CLIENT.STREET') }}
                <input v-model="form.endereco" maxlength="80" :class="INPUT" />
              </label>
              <label :class="LABEL" class="sm:col-span-1">
                {{ t('OUTSIDER_ERP.CLIENT.NUMBER') }}
                <input v-model="form.numero" maxlength="10" :class="INPUT" />
              </label>
              <label :class="LABEL" class="sm:col-span-2">
                {{ t('OUTSIDER_ERP.CLIENT.DISTRICT') }}
                <input v-model="form.bairro" maxlength="40" :class="INPUT" />
              </label>
              <label :class="LABEL" class="sm:col-span-3">
                {{ t('OUTSIDER_ERP.CLIENT.CITY') }}
                <input v-model="form.cidade" maxlength="40" :class="INPUT" />
              </label>
              <label :class="LABEL" class="sm:col-span-1">
                {{ t('OUTSIDER_ERP.CLIENT.UF') }}
                <select v-model="form.uf" :class="SELECT">
                  <option value="">—</option>
                  <option v-for="uf in UFS" :key="uf" :value="uf">
                    {{ uf }}
                  </option>
                </select>
              </label>
              <label :class="LABEL" class="sm:col-span-6">
                {{ t('OUTSIDER_ERP.CLIENT.REFERENCE') }}
                <input
                  v-model="form.referencia"
                  maxlength="60"
                  :class="INPUT"
                />
              </label>
            </div>
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="form.copiar_endereco"
                type="checkbox"
                class="!m-0"
              />
              {{ t('OUTSIDER_ERP.CLIENT.COPY_ADDRESS') }}
            </label>
          </section>

          <section class="grid gap-3 sm:grid-cols-6">
            <h4 class="mb-0 text-sm font-medium sm:col-span-6 text-n-slate-12">
              {{ t('OUTSIDER_ERP.CLIENT.CONTACT') }}
            </h4>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.CONTACT_NAME') }}
              <input
                v-model="form.contato_nome"
                maxlength="50"
                :class="INPUT"
              />
            </label>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.PHONE') }}
              <input
                v-model="form.contato_telefone"
                maxlength="20"
                inputmode="tel"
                :class="INPUT"
              />
            </label>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.EMAIL') }}
              <input
                v-model="form.contato_email"
                maxlength="100"
                type="email"
                :class="[INPUT, showError('contato_email') && BAD]"
              />
            </label>
            <label :class="LABEL" class="sm:col-span-2">
              {{ t('OUTSIDER_ERP.CLIENT.SELLER') }}
              <select v-model.number="form.vendedor" :class="SELECT">
                <option :value="0">
                  {{ t('OUTSIDER_ERP.CLIENT.NO_SELLER') }}
                </option>
                <option
                  v-for="item in sellers"
                  :key="item.codigo"
                  :value="item.codigo"
                >
                  {{ item.codigo }} · {{ item.nome }}
                </option>
              </select>
            </label>
            <label :class="LABEL" class="sm:col-span-4">
              {{ t('OUTSIDER_ERP.CLIENT.NOTES') }}
              <input
                v-model="form.observacoes"
                maxlength="400"
                :class="INPUT"
              />
            </label>
          </section>
        </div>

        <footer
          class="flex flex-wrap items-center justify-between gap-3 px-5 py-3 border-t shrink-0 border-n-weak bg-n-alpha-1"
        >
          <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
            <Icon icon="i-lucide-database" class="size-3.5 shrink-0" />
            {{
              t('OUTSIDER_ERP.CLIENT.WRITES_TO', {
                company: companyName(company),
              })
            }}
          </span>
          <div class="flex items-center gap-2 ms-auto">
            <Button
              type="button"
              variant="faded"
              color="slate"
              size="sm"
              :label="t('OUTSIDER_ERP.CANCEL')"
              :disabled="saving"
              @click="close"
            />
            <Button
              type="submit"
              size="sm"
              icon="i-lucide-user-plus"
              :label="t('OUTSIDER_ERP.CLIENT.SAVE')"
              :is-loading="saving"
              :disabled="Boolean(existing) || saving"
            />
          </div>
        </footer>
      </form>
    </div>
  </Teleport>
</template>
