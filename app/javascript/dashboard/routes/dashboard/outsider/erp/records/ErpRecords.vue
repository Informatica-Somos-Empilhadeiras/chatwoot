<script setup>
// OUTSIDER: uma aba da seção ERP (orçamentos, OS ou pedidos) com TODO o histórico lido direto do banco do ERP: visões
// rápidas com contagem, busca (número, cliente, CNPJ), unidade, vendedor/técnico (na OS também tipo de atendimento e
// vendedor), período, ordenação, tabela paginada e o painel de detalhe ao lado. O registro aberto fica na rota (?open=empresa:número); os nós da corrente orçamento -> OS ->
// pedido trocam o painel sem sair da aba. ?contact=<id> mostra só os clientes do ERP ligados àquele contato.
// ?machine=<cadastro base>:<número> ("Ver OS da máquina" da ficha) mostra só as OS daquela máquina, em todas as situações.
// Locação e máquinas (contratos, máquinas, faturas de locação) usam a tabela e o painel de rentals/; máquina não tem
// pessoa nem período.
import { ref, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpRecordsTable from './ErpRecordsTable.vue';
import { fetchCloud, cloudKey } from './invoiceCloud';
import ErpRecordsPager from './ErpRecordsPager.vue';
import ErpRecordPanel from './ErpRecordPanel.vue';
import ErpRentalTable from '../rentals/ErpRentalTable.vue';
import ErpRentalPanel from '../rentals/ErpRentalPanel.vue';
import ErpBudgetDrawer from '../budgets/ErpBudgetDrawer.vue';
import ErpOrderDrawer from '../orders/ErpOrderDrawer.vue';
import { orderErrorMessage } from '../orders/orderHelpers';
import {
  erpState,
  erpErrorMessage,
  formatMoney,
  companyName,
} from '../erpStore';
import { budgetErrorMessage } from '../budgets/budgetHelpers';
import {
  DIMENSIONS,
  KINDS,
  PER_PAGE,
  PERIODS,
  periodRange,
  parseKey,
  recordKey,
  shortName,
  sortOptions,
  titleCase,
} from './recordsConfig';

const props = defineProps({
  kind: { type: String, required: true },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const PER_KEY = 'outsider-erp-records-per';
const storedPer = () => {
  try {
    const value = Number(window.localStorage.getItem(PER_KEY));
    return PER_PAGE.includes(value) ? value : 50;
  } catch {
    return 50;
  }
};

const q = ref('');
// OS de uma máquina: todas as situações
const view = ref(route.query.machine ? 'all' : '');
const company = ref('');
const person = ref('');
const period = ref('all');
const from = ref('');
const to = ref('');
const page = ref(1);
const per = ref(storedPer());
const sort = ref('data');
const direction = ref('desc');
// filtros extras do tipo (OS: atendimento, vendedor), valor escolhido por filtro
const picked = ref({});
const data = ref(null);
const loading = ref(false);
const failure = ref('');
const busy = ref('');
const drawerRef = ref(null);
let sequence = 0;

const cfg = computed(() => KINDS[props.kind]);
const label = key => t(`OUTSIDER_ERP.RECORDS.${cfg.value.key}.${key}`);
const opened = computed(() => parseKey(route.query.open));
const contactId = computed(() => Number(route.query.contact) || null);
const machine = computed(() => route.query.machine || '');

const dimensionKeys = computed(() => DIMENSIONS[props.kind] || []);

const params = computed(() => ({
  ...Object.fromEntries(
    dimensionKeys.value.map(key => [key, picked.value[key] || undefined])
  ),
  q: q.value || undefined,
  view: view.value || undefined,
  company: company.value || undefined,
  person: person.value || undefined,
  from: from.value || undefined,
  to: to.value || undefined,
  page: page.value,
  per: per.value,
  sort: sort.value,
  direction: direction.value,
  contact_id: contactId.value || undefined,
  machine: machine.value || undefined,
}));

// NF-e/NFS-e: aviso das que ainda não estão na nuvem (só as linhas desta página)
const cloud = ref({});
const loadCloud = async rows => {
  const kind = props.kind;
  const keys = rows.map(row => cloudKey(kind, row.banco, row.numero));
  cloud.value = {};
  const statuses = await fetchCloud(kind, keys);
  if (kind === props.kind) cloud.value = statuses;
};

const load = async () => {
  sequence += 1;
  const mine = sequence;
  loading.value = true;
  failure.value = '';
  try {
    const response = await ErpAPI.records(props.kind, params.value);
    if (mine !== sequence) return;
    data.value = response.data;
    if (!view.value) view.value = response.data.view;
    loadCloud(response.data.items || []);
  } catch (error) {
    if (mine === sequence) failure.value = erpErrorMessage(t, error);
  } finally {
    if (mine === sequence) loading.value = false;
  }
};

const reload = () => {
  if (page.value === 1) load();
  else page.value = 1;
};
const searchLater = debounce(reload, 350);

watch(q, searchLater);
watch(machine, value => {
  if (value) view.value = 'all';
});
watch([view, company, person, from, to, contactId, machine, picked], reload, {
  deep: true,
});
watch([page, per, sort, direction], load);
watch(per, value => {
  try {
    window.localStorage.setItem(PER_KEY, String(value));
  } catch {
    // navegador sem armazenamento: só não lembra
  }
});
load();

watch(period, value => {
  if (value === 'custom') return;
  const range = periodRange(value);
  from.value = range.from;
  to.value = range.to;
});

const viewLabel = item => {
  if (item.label) return item.label;
  const key = `OUTSIDER_ERP.RECORDS.${cfg.value.key}.VIEWS.${item.key.toUpperCase()}`;
  const text = t(key);
  return text === key ? item.key : text;
};

const TEXT_SORTS = ['cliente', 'pessoa', 'atendimento', 'vendedor'];
const toggleSort = key => {
  if (sort.value === key) {
    direction.value = direction.value === 'desc' ? 'asc' : 'desc';
  } else {
    sort.value = key;
    direction.value = TEXT_SORTS.includes(key) ? 'asc' : 'desc';
  }
};

const sorts = computed(() => sortOptions(props.kind));
const sortValue = computed({
  get: () => `${sort.value}:${direction.value}`,
  set: value => {
    const [key, dir] = String(value).split(':');
    sort.value = key;
    direction.value = dir;
  },
});
const sortLabel = item =>
  item.key === 'PERSON_AZ'
    ? t('OUTSIDER_ERP.RECORDS.SORTS.PERSON_AZ', { person: label('PERSON') })
    : t(`OUTSIDER_ERP.RECORDS.SORTS.${item.key}`);

// opções de cada filtro extra (com contagem); a escolha atual fica mesmo se a lista nova não a tiver
const dimensionOptions = key => {
  const list = data.value?.dimensions?.[key] || [];
  const current = picked.value[key];
  if (!current || list.some(item => String(item.value) === String(current)))
    return list;
  return [{ value: current, name: null, count: 0 }, ...list];
};
const dimensionText = (key, item) =>
  key === 'vendedor'
    ? shortName(item.name) || `#${item.value}`
    : titleCase(item.value);
const setDimension = (key, value) => {
  picked.value = { ...picked.value, [key]: value };
};

const setQuery = changes => {
  const query = { ...route.query, ...changes };
  Object.keys(query).forEach(key => {
    if (query[key] === undefined || query[key] === '') delete query[key];
  });
  router.replace({ query });
};

const select = row => setQuery({ open: recordKey(row) });
const close = () => setQuery({ open: undefined });
const clearContact = () => setQuery({ contact: undefined });
const clearMachine = () =>
  setQuery({ machine: undefined, machine_name: undefined });

// orçamento novo direto da seção (o cliente é escolhido na gaveta)
const createBudget = async () => {
  busy.value = 'new';
  try {
    const response = await ErpAPI.createBudget({
      contact_id: contactId.value || undefined,
    });
    drawerRef.value?.open(response.data.budget, { focus: true });
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

// OS nova direto da aba OS (com a OS pelo chat ligada): o cliente é escolhido na gaveta
const orderDrawerRef = ref(null);
const createOrder = async () => {
  busy.value = 'new';
  try {
    const { data: created } = await ErpAPI.createOrderDraft({
      kind: 'fresh',
      contact_id: contactId.value || undefined,
    });
    orderDrawerRef.value?.open(created.draft, { focus: true });
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const summary = computed(() => {
  if (!data.value) return '';
  return t(`OUTSIDER_ERP.RECORDS.${cfg.value.key}.SUMMARY`, {
    count: Number(data.value.total || 0).toLocaleString('pt-BR'),
    sum: formatMoney(data.value.sum),
  });
});

const SELECT =
  '!mb-0 !w-auto max-w-[14rem] h-9 pl-3 !pr-8 py-0 text-[13px] rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
const DATE =
  '!mb-0 !w-auto h-9 px-2 text-[13px] rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
</script>

<template>
  <div class="flex w-full h-full min-h-0 gap-0">
    <section class="flex flex-col flex-1 min-w-0 min-h-0 pb-4">
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="item in data?.views || []"
          :key="item.key"
          type="button"
          class="flex items-center gap-2 h-8 px-3 text-[13px] rounded-full transition-colors"
          :class="
            view === item.key
              ? 'bg-n-slate-12 text-n-slate-1 font-medium'
              : 'bg-n-alpha-1 text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak hover:bg-n-alpha-2'
          "
          @click="view = item.key"
        >
          {{ viewLabel(item) }}
          <span
            class="tabular-nums"
            :class="view === item.key ? 'text-n-slate-6' : 'text-n-slate-10'"
          >
            {{ Number(item.count).toLocaleString('pt-BR') }}
          </span>
        </button>
        <span class="flex-1" />
        <Button
          v-if="kind === 'quotes' && erpState.canCreateQuote"
          size="sm"
          icon="i-lucide-plus"
          :label="t('OUTSIDER_ERP.RECORDS.QUOTES.NEW')"
          :is-loading="busy === 'new'"
          @click="createBudget"
        />
        <Button
          v-if="kind === 'orders' && erpState.canCreateOrder"
          size="sm"
          icon="i-lucide-plus"
          :label="t('OUTSIDER_ERP.ORDER_DRAFT.NEW')"
          :is-loading="busy === 'new'"
          data-erp-records-new-order
          @click="createOrder"
        />
      </div>

      <div class="flex flex-wrap items-center gap-2 mt-3">
        <label
          class="flex items-center flex-1 min-w-[14rem] gap-2 px-3 h-9 rounded-lg bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-slate-6 focus-within:outline-n-brand"
        >
          <Icon
            icon="i-lucide-search"
            class="size-4 text-n-slate-10 shrink-0"
          />
          <input
            v-model="q"
            type="search"
            class="!mb-0 flex-1 min-w-0 h-full text-sm bg-transparent reset-base text-n-slate-12 placeholder:text-n-slate-10"
            :placeholder="label('SEARCH')"
          />
          <Spinner v-if="loading && data" class="size-3.5 text-n-slate-10" />
        </label>
        <select
          v-if="(data?.companies || []).length > 1 || company"
          v-model="company"
          :class="SELECT"
          :aria-label="t('OUTSIDER_ERP.RECORDS.UNIT')"
        >
          <option value="">{{ t('OUTSIDER_ERP.RECORDS.ALL_UNITS') }}</option>
          <option
            v-for="item in data?.companies || []"
            :key="item.value"
            :value="item.value"
          >
            {{ companyName(item.value) }} ({{ item.count }})
          </option>
        </select>
        <select
          v-if="!cfg.noPerson"
          v-model="person"
          :class="SELECT"
          :aria-label="label('PERSON')"
        >
          <option value="">{{ label('ALL_PEOPLE') }}</option>
          <option
            v-for="item in data?.people || []"
            :key="item.code"
            :value="String(item.code)"
          >
            {{ shortName(item.name) }} ({{ item.count }})
          </option>
        </select>
        <select
          v-for="key in dimensionKeys"
          :key="key"
          :value="picked[key] || ''"
          :class="SELECT"
          :aria-label="
            t(`OUTSIDER_ERP.RECORDS.DIMENSIONS.${key.toUpperCase()}.LABEL`)
          "
          :data-dimension="key"
          @change="setDimension(key, $event.target.value)"
        >
          <option value="">
            {{ t(`OUTSIDER_ERP.RECORDS.DIMENSIONS.${key.toUpperCase()}.ALL`) }}
          </option>
          <option
            v-for="item in dimensionOptions(key)"
            :key="item.value"
            :value="String(item.value)"
          >
            {{ dimensionText(key, item) }} ({{ item.count }})
          </option>
        </select>
        <select
          v-if="!cfg.noPeriod"
          v-model="period"
          :class="SELECT"
          :aria-label="t('OUTSIDER_ERP.RECORDS.PERIOD')"
        >
          <option v-for="key in PERIODS" :key="key" :value="key">
            {{ t(`OUTSIDER_ERP.RECORDS.PERIODS.${key.toUpperCase()}`) }}
          </option>
        </select>
        <template v-if="period === 'custom' && !cfg.noPeriod">
          <input
            v-model="from"
            type="date"
            :class="DATE"
            :aria-label="t('OUTSIDER_ERP.RECORDS.FROM')"
          />
          <input
            v-model="to"
            type="date"
            :class="DATE"
            :aria-label="t('OUTSIDER_ERP.RECORDS.TO')"
          />
        </template>
        <label class="flex items-center gap-1.5 text-xs text-n-slate-10">
          <Icon icon="i-lucide-arrow-down-up" class="size-3.5 shrink-0" />
          <select
            v-model="sortValue"
            :class="SELECT"
            :aria-label="t('OUTSIDER_ERP.RECORDS.SORT')"
            data-sort
          >
            <option v-for="item in sorts" :key="item.value" :value="item.value">
              {{ sortLabel(item) }}
            </option>
          </select>
        </label>
      </div>

      <div
        class="flex flex-wrap items-center justify-between gap-2 mt-3 mb-2 text-xs text-n-slate-10"
      >
        <span class="flex flex-wrap items-center gap-2">
          <span
            v-if="data?.contact"
            class="inline-flex items-center gap-1.5 h-6 pl-2.5 pr-1 rounded-full bg-n-blue-3 text-n-blue-11"
          >
            {{
              t('OUTSIDER_ERP.RECORDS.CONTACT_SCOPE', {
                name: data.contact.name,
              })
            }}
            <button
              type="button"
              class="grid rounded-full size-5 place-content-center hover:bg-n-blue-4"
              :aria-label="t('OUTSIDER_ERP.RECORDS.CLEAR_CONTACT')"
              @click="clearContact"
            >
              <Icon icon="i-lucide-x" class="size-3" />
            </button>
          </span>
          <span
            v-if="machine"
            class="inline-flex items-center gap-1.5 h-6 pl-2.5 pr-1 rounded-full bg-n-blue-3 text-n-blue-11"
            data-machine-scope
          >
            {{
              t('OUTSIDER_ERP.RECORDS.MACHINE_SCOPE', {
                name:
                  route.query.machine_name ||
                  `#${String(machine).split(':')[1] || ''}`,
              })
            }}
            <button
              type="button"
              class="grid rounded-full size-5 place-content-center hover:bg-n-blue-4"
              :aria-label="t('OUTSIDER_ERP.RECORDS.CLEAR_MACHINE')"
              @click="clearMachine"
            >
              <Icon icon="i-lucide-x" class="size-3" />
            </button>
          </span>
          <span>{{ summary }}</span>
        </span>
        <span>{{ t('OUTSIDER_ERP.RECORDS.LIVE') }}</span>
      </div>

      <div
        class="flex flex-col flex-1 min-h-[20rem] overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div
          v-if="failure && !data"
          class="flex flex-col items-center justify-center flex-1 gap-3 p-8 text-center"
        >
          <Icon icon="i-lucide-cloud-off" class="size-8 text-n-slate-9" />
          <p class="max-w-md mb-0 text-sm text-n-slate-11">{{ failure }}</p>
          <Button
            size="sm"
            variant="faded"
            color="slate"
            :label="t('OUTSIDER_ERP.CONTACT.RETRY')"
            @click="load"
          />
        </div>
        <div v-else-if="!data" class="flex items-center justify-center flex-1">
          <Spinner class="text-n-slate-10" />
        </div>
        <template v-else>
          <p
            v-if="failure"
            class="px-4 py-2 mb-0 text-xs border-b text-n-ruby-11 bg-n-ruby-2 border-n-weak"
          >
            {{ failure }}
          </p>
          <ErpRentalTable
            v-if="cfg.rental"
            class="flex-1 min-h-0"
            :kind="kind"
            :rows="data.items || []"
            :sort="sort"
            :direction="direction"
            :selected="opened ? `${opened.company}:${opened.number}` : ''"
            :loading="loading"
            :compact="!!opened"
            @select="select"
            @sort="toggleSort"
          />
          <ErpRecordsTable
            v-else
            class="flex-1 min-h-0"
            :kind="kind"
            :rows="data.items || []"
            :cloud="cloud"
            :sort="sort"
            :direction="direction"
            :selected="opened ? `${opened.company}:${opened.number}` : ''"
            :loading="loading"
            :compact="!!opened"
            @select="select"
            @sort="toggleSort"
          />
          <ErpRecordsPager
            v-model:page="page"
            v-model:per="per"
            :total="data.total || 0"
            :options="PER_PAGE"
          />
        </template>
      </div>
    </section>

    <ErpRentalPanel
      v-if="opened && cfg.rental"
      :key="`${kind}:${opened.company}:${opened.number}`"
      :kind="kind"
      :company="opened.company"
      :number="opened.number"
      @close="close"
    />
    <ErpRecordPanel
      v-else-if="opened"
      :key="`${kind}:${opened.company}:${opened.number}`"
      :kind="kind"
      :company="opened.company"
      :number="opened.number"
      @close="close"
      @changed="load"
    />
    <ErpBudgetDrawer ref="drawerRef" :contact-id="contactId" @changed="load" />
    <ErpOrderDrawer
      v-if="kind === 'orders' && erpState.canCreateOrder"
      ref="orderDrawerRef"
      :contact-id="contactId"
    />
  </div>
</template>
