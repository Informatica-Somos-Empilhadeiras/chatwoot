<script setup>
// OUTSIDER: linha "Adicionar peça ou serviço" do orçamento. Ao focar, a lista de produtos da unidade já abre pronta;
// digitar só filtra (código, código de fábrica ou palavras do nome). Na peça marcada (setas ou mouse) a pessoa já acerta
// quantidade, valor e desconto e tecla Enter: o item entra e o cursor volta para a busca, pronto para a próxima.
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpErrorMessage, formatMoney } from '../erpStore';
import { formatNumber, formatQty, parseNumber } from './budgetHelpers';

const props = defineProps({
  company: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['add']);

const { t } = useI18n();
const searchRef = ref(null);
const query = ref('');
const open = ref(false);
const loading = ref(false);
const failure = ref('');
const products = ref([]);
const active = ref(0);
const entry = ref({ quantidade: '1', preco: '', desconto: '0' });
const technical = ref({});
const technicalOpen = ref(null);
let lastRun = 0;

const current = computed(() => products.value[active.value]);

const resetEntry = product => {
  entry.value = {
    quantidade: '1',
    preco: product ? formatNumber(product.preco) : '',
    desconto: '0',
  };
};

watch(current, product => resetEntry(product));

const load = async () => {
  lastRun += 1;
  const mine = lastRun;
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.catalog(props.company, query.value.trim());
    if (mine !== lastRun) return;
    products.value = data.products || [];
    active.value = 0;
    resetEntry(products.value[0]);
  } catch (error) {
    if (mine === lastRun) {
      products.value = [];
      failure.value = erpErrorMessage(t, error);
    }
  } finally {
    if (mine === lastRun) loading.value = false;
  }
};

const loadLater = debounce(load, 300);
watch(query, () => open.value && loadLater());
watch(
  () => props.company,
  () => {
    products.value = [];
    if (open.value) load();
  }
);

const show = () => {
  if (props.disabled) return;
  open.value = true;
  if (!products.value.length && !loading.value) load();
};

const hide = () => {
  open.value = false;
  technicalOpen.value = null;
};

// Esc fecha só a lista (não a gaveta inteira); com a lista fechada, o Esc segue para a gaveta
const onEsc = event => {
  if (!open.value) return;
  event.stopPropagation();
  hide();
};

// fecha ao sair de todo o bloco (busca + lista), não ao ir da busca para a quantidade
const onFocusOut = event => {
  if (!event.currentTarget.contains(event.relatedTarget)) hide();
};

const move = step => {
  if (!products.value.length) return;
  open.value = true;
  active.value =
    (active.value + step + products.value.length) % products.value.length;
  nextTick(() =>
    document
      .getElementById(`erp-product-${active.value}`)
      ?.scrollIntoView({ block: 'nearest' })
  );
};

const add = (product = current.value) => {
  if (!product || product.bloqueado) return;
  emit('add', {
    codigo: product.codigo,
    descricao: product.descricao,
    unidade: product.unidade || '',
    tipo: product.tipo,
    ncm: product.ncm || '',
    quantidade: parseNumber(entry.value.quantidade, 1),
    preco: parseNumber(entry.value.preco, product.preco),
    desconto: parseNumber(entry.value.desconto),
  });
  query.value = '';
  resetEntry(product);
  nextTick(() => searchRef.value?.focus());
};

const pick = (index, focusField = false) => {
  active.value = index;
  if (focusField)
    nextTick(() => document.getElementById('erp-entry-qty')?.select());
};

const toggleTechnical = async product => {
  if (technicalOpen.value === product.codigo) {
    technicalOpen.value = null;
    return;
  }
  technicalOpen.value = product.codigo;
  if (technical.value[product.codigo] !== undefined) return;
  try {
    const { data } = await ErpAPI.technical(props.company, product.codigo);
    technical.value = { ...technical.value, [product.codigo]: data.technical };
  } catch {
    technical.value = { ...technical.value, [product.codigo]: '' };
  }
};

const stockText = product => {
  if (product.tipo === 1) return '';
  if (product.estoque === null || product.estoque === undefined) return '';
  return product.estoque > 0
    ? t('OUTSIDER_ERP.BUDGET.ITEMS.STOCK', {
        count: formatQty(product.estoque),
      })
    : t('OUTSIDER_ERP.BUDGET.ITEMS.NO_STOCK');
};

const INPUT =
  '!mb-0 h-8 px-2 text-sm text-right rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';

defineExpose({ focus: () => searchRef.value?.focus() });
</script>

<template>
  <div class="relative" @focusout="onFocusOut">
    <div class="relative">
      <Icon
        icon="i-lucide-search"
        class="absolute -translate-y-1/2 pointer-events-none size-4 left-3 top-1/2 text-n-slate-10"
      />
      <input
        ref="searchRef"
        v-model="query"
        type="text"
        :disabled="disabled"
        :placeholder="t('OUTSIDER_ERP.BUDGET.ITEMS.SEARCH')"
        class="!mb-0 w-full h-10 pl-9 pr-9 text-sm rounded-xl reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-2 focus:outline-n-brand disabled:opacity-60"
        @focus="show"
        @click="show"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="open && add()"
        @keydown.esc="onEsc"
      />
      <Spinner
        v-if="loading"
        class="absolute -translate-y-1/2 right-3 top-1/2 size-4 text-n-slate-10"
      />
    </div>

    <div
      v-if="open"
      tabindex="-1"
      class="absolute left-0 right-0 z-30 outline-none mt-1 overflow-y-auto border shadow-lg max-h-96 rounded-xl border-n-weak bg-n-solid-1"
    >
      <p v-if="failure" class="p-3 mb-0 text-xs text-n-ruby-11">
        {{ failure }}
        <button type="button" class="underline" @click="load">
          {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
        </button>
      </p>
      <p
        v-else-if="!products.length && !loading"
        class="p-3 mb-0 text-xs text-n-slate-10"
      >
        {{ t('OUTSIDER_ERP.BUDGET.ITEMS.NONE') }}
      </p>
      <div
        v-for="(product, index) in products"
        :id="`erp-product-${index}`"
        :key="product.codigo"
        class="flex flex-col gap-2 px-3 py-2 border-b cursor-pointer last:border-b-0 border-n-weak"
        :class="index === active ? 'bg-n-teal-2' : 'hover:bg-n-alpha-1'"
        @mouseenter="pick(index)"
        @click="pick(index, true)"
      >
        <div class="flex items-center gap-3">
          <span
            class="flex items-center justify-center rounded-lg shrink-0 size-8 bg-n-alpha-2 text-n-slate-11"
          >
            <Icon
              :icon="
                product.tipo === 1 ? 'i-lucide-wrench' : 'i-lucide-package'
              "
              class="size-4"
            />
          </span>
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ product.codigo }} · {{ product.descricao }}
            </span>
            <span
              class="flex flex-wrap items-center text-xs gap-x-2 text-n-slate-10"
            >
              <span v-if="product.unidade">{{ product.unidade }}</span>
              <span v-if="product.ncm">{{
                t('OUTSIDER_ERP.BUDGET.ITEMS.NCM', { ncm: product.ncm })
              }}</span>
              <span v-if="product.fabrica">{{ product.fabrica }}</span>
              <span
                v-if="product.tipo === 1"
                class="px-1.5 rounded bg-n-blue-3 text-n-blue-11"
              >
                {{ t('OUTSIDER_ERP.BUDGET.ITEMS.SERVICE') }}
              </span>
              <span
                v-else-if="stockText(product)"
                :class="
                  product.estoque > 0 ? 'text-n-teal-11' : 'text-n-ruby-11'
                "
              >
                {{ stockText(product) }}
              </span>
              <span v-if="product.bloqueado" class="text-n-ruby-11">
                {{ t('OUTSIDER_ERP.BUDGET.ITEMS.BLOCKED') }}
              </span>
              <button
                type="button"
                class="text-n-blue-11 hover:underline"
                @click.stop="toggleTechnical(product)"
              >
                {{ t('OUTSIDER_ERP.BUDGET.ITEMS.TECHNICAL') }}
              </button>
            </span>
          </div>
          <span
            v-if="index !== active"
            class="text-sm font-medium whitespace-nowrap text-n-slate-12"
          >
            {{ formatMoney(product.preco) }}
          </span>
        </div>
        <p
          v-if="technicalOpen === product.codigo"
          class="mb-0 ml-11 text-xs whitespace-pre-line text-n-slate-11"
        >
          {{
            technical[product.codigo] === undefined
              ? t('OUTSIDER_ERP.QUOTES.LOADING')
              : technical[product.codigo] ||
                t('OUTSIDER_ERP.BUDGET.ITEMS.NO_TECHNICAL')
          }}
        </p>
        <!-- peça marcada: quantidade, valor e desconto já aqui; Enter adiciona -->
        <div
          v-if="index === active && !product.bloqueado"
          class="flex flex-wrap items-end justify-end gap-2 ml-11"
          @click.stop
        >
          <label class="flex flex-col gap-0.5 text-xs text-n-slate-11">
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.QTY') }}
            <input
              id="erp-entry-qty"
              v-model="entry.quantidade"
              inputmode="decimal"
              :class="INPUT"
              class="w-16"
              @keydown.enter.prevent="add()"
              @keydown.esc="onEsc"
            />
          </label>
          <label class="flex flex-col gap-0.5 text-xs text-n-slate-11">
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.PRICE') }}
            <input
              v-model="entry.preco"
              inputmode="decimal"
              :class="INPUT"
              class="w-28"
              @keydown.enter.prevent="add()"
              @keydown.esc="onEsc"
            />
          </label>
          <label class="flex flex-col gap-0.5 text-xs text-n-slate-11">
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.DISCOUNT') }}
            <input
              v-model="entry.desconto"
              inputmode="decimal"
              :class="INPUT"
              class="w-16"
              @keydown.enter.prevent="add()"
              @keydown.esc="onEsc"
            />
          </label>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm font-medium text-white rounded-lg bg-n-brand hover:opacity-90"
            @click="add()"
          >
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.ADD') }}
            <Icon icon="i-lucide-corner-down-left" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
