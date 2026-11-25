<script setup>
// OUTSIDER: campo "Máquina" da OS feita no chat. A lista já abre com as máquinas do cliente (cadastro dele e contratos
// ativos, Outsider::Erp::Orders::Options#machines), com série e o último horímetro; "Buscar outra máquina" procura em
// todas as máquinas da unidade (como desmarcar "só máquinas do cliente" no desktop). O valor é o pedaço dos campos da OS
// que fala da máquina: { maquina, maquina_descricao, serie, maquina_do_cliente }.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpPicker from '../components/ErpPicker.vue';
import { erpErrorMessage } from '../erpStore';
import { machineLabel } from './orderHelpers';

const props = defineProps({
  company: { type: String, required: true },
  customer: { type: [Number, String], default: null },
  kind: { type: String, default: 'fresh' },
  required: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  invalid: { type: Boolean, default: false },
});

const emit = defineEmits(['lastHours']);

const value = defineModel({ type: Object, default: () => ({}) });

const { t } = useI18n();
const machines = ref([]);
const loading = ref(false);
const failure = ref('');
const searching = ref(false);
const SEARCH = '__search__';

const load = async () => {
  if (!props.company || !props.customer) {
    machines.value = [];
    return;
  }
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.orderMachines(
      props.company,
      props.customer,
      '',
      props.kind
    );
    machines.value = data.machines || [];
  } catch (error) {
    machines.value = [];
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

watch(() => [props.company, props.customer], load, { immediate: true });

// a escolhida entra na lista mesmo quando veio da busca (ou de um rascunho salvo)
const options = computed(() => {
  const code = Number(value.value.maquina);
  if (!code || machines.value.some(item => Number(item.codigo) === code))
    return machines.value;
  return [
    {
      codigo: code,
      descricao: value.value.maquina_descricao,
      serie: value.value.serie,
      do_cliente: value.value.maquina_do_cliente === false ? 0 : 1,
    },
    ...machines.value,
  ];
});

const current = computed(() =>
  options.value.find(
    item => Number(item.codigo) === Number(value.value.maquina)
  )
);

watch(current, item => emit('lastHours', item?.horimetro || ''), {
  immediate: true,
});

const choose = item => {
  searching.value = false;
  if (!item) {
    value.value = {
      maquina: null,
      maquina_descricao: null,
      serie: null,
      maquina_do_cliente: true,
    };
    return;
  }
  if (!machines.value.some(row => Number(row.codigo) === Number(item.codigo)))
    machines.value = [item, ...machines.value];
  value.value = {
    maquina: Number(item.codigo),
    maquina_descricao: [item.descricao, item.modelo]
      .filter(Boolean)
      .join(' ')
      .slice(0, 150),
    serie: item.serie || null,
    maquina_do_cliente: Number(item.do_cliente) === 1,
  };
};

const onSelect = event => {
  const picked = event.target.value;
  if (picked === SEARCH) {
    searching.value = true;
    event.target.value = value.value.maquina ? String(value.value.maquina) : '';
    return;
  }
  choose(machines.value.find(item => String(item.codigo) === picked) || null);
};

const searchMachines = async q => {
  const { data } = await ErpAPI.orderMachines(
    props.company,
    props.customer,
    q || '',
    props.kind
  );
  return data.machines || [];
};

const optionText = item => {
  const extra = [];
  if (Number(item.do_cliente) !== 1)
    extra.push(t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_OTHER'));
  return [machineLabel(item), ...extra].join(' · ');
};

const SELECT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand disabled:opacity-70 normal-case !pr-7 bg-[right_-1.25rem_center]';
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <div class="relative">
      <select
        :value="value.maquina ? String(value.maquina) : ''"
        :disabled="disabled || loading"
        :class="[SELECT, invalid && '!outline-n-ruby-9']"
        data-erp-order-machine
        @change="onSelect"
      >
        <option value="" :disabled="required">
          {{
            required
              ? t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_PICK')
              : t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_NONE')
          }}
        </option>
        <option
          v-for="item in options"
          :key="item.codigo"
          :value="String(item.codigo)"
        >
          {{ optionText(item) }}
        </option>
        <option :value="SEARCH">
          {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_SEARCH') }}
        </option>
      </select>
      <Spinner
        v-if="loading"
        class="absolute -translate-y-1/2 right-7 top-1/2 size-3.5 text-n-slate-10"
      />
    </div>
    <p v-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
      <button type="button" class="underline" @click="load">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>
    <p
      v-else-if="!loading && customer && !machines.length && !searching"
      class="mb-0 text-xs text-n-slate-10"
    >
      {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_NO_CUSTOMER') }}
      <button
        v-if="!disabled"
        type="button"
        class="underline"
        @click="searching = true"
      >
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_SEARCH') }}
      </button>
    </p>
    <div v-if="searching" class="flex flex-col gap-1">
      <ErpPicker
        :source="`${company}:${customer}`"
        :search="searchMachines"
        :row-key="row => String(row.codigo)"
        :placeholder="t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_SEARCH_HINT')"
        :empty-text="t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_EMPTY')"
        @select="choose"
      >
        <template #row="{ row }">
          <span class="text-xs font-medium truncate text-n-slate-12">
            {{ machineLabel(row) }}
          </span>
          <span class="text-xs truncate text-n-slate-10">
            {{
              [
                `#${row.codigo}`,
                row.patrimonio &&
                  t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_ASSET', {
                    value: row.patrimonio,
                  }),
                Number(row.do_cliente) !== 1 &&
                  t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_OTHER'),
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
        </template>
      </ErpPicker>
      <button
        type="button"
        class="inline-flex items-center self-start gap-1 text-xs text-n-slate-11 hover:underline"
        @click="searching = false"
      >
        <Icon icon="i-lucide-x" class="size-3" />
        {{ t('OUTSIDER_ERP.CANCEL') }}
      </button>
    </div>
  </div>
</template>
