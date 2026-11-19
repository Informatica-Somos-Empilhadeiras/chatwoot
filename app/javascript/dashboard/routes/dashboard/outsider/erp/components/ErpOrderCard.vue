<script setup>
// OUTSIDER: uma ordem de serviço do ERP (espelho). Fechada mostra o essencial; aberta mostra os detalhes e, para quem
// pode editar (escrita ligada + perfil "Usa"), troca o substatus e os campos liberados nas Configurações. A gravação
// vai para o ERP na hora (Outsider::Erp::Writer) e, numa conversa, deixa uma nota privada dizendo o que mudou.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  erpState,
  formatDate,
  dotClass,
  substatusClass,
  erpErrorMessage,
} from '../erpStore';

const props = defineProps({
  order: { type: Object, required: true },
  options: { type: Array, default: () => [] },
  conversationId: { type: [Number, String], default: null },
  startOpen: { type: Boolean, default: false },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const open = ref(props.startOpen);
const substatus = ref(props.order.SubStatus || '');
const drafts = ref({});
const saving = ref('');

const resetDrafts = () => {
  substatus.value = props.order.SubStatus || '';
  drafts.value = Object.fromEntries(
    erpState.fields.map(field => [field, props.order[field] ?? ''])
  );
};
watch(() => props.order, resetDrafts, { immediate: true });

const late = computed(() => Number(props.order.DiasAtraso) > 0);
const substatusOptions = computed(() =>
  props.options.includes(props.order.SubStatus) || !props.order.SubStatus
    ? props.options
    : [props.order.SubStatus, ...props.options]
);

const fieldLabel = field => {
  const key = `OUTSIDER_ERP.FIELDS.${field.toUpperCase()}`;
  const label = t(key);
  return label === key ? field : label;
};

const details = computed(() =>
  [
    ['SITUATION', props.order.Situacao],
    ['SERVICE', props.order.TipoAtendimento],
    [
      'KIND',
      [props.order.Classe, props.order.TipoOS].filter(Boolean).join(' · '),
    ],
    ['SERIAL', props.order.NSerie],
    ['MACHINE_STATUS', props.order.StatusMaquina],
    ['OWNERSHIP', props.order.PropriedadeMaquina],
    ['SELLER', props.order.NomeVendedor],
    ['ATTENDANT', props.order.NomeAtendente],
    ['DELIVERY', formatDate(props.order.DataEntrega)],
    ['LAST_STATUS', formatDate(props.order.DtUltimoStatus)],
    [
      'ITEMS',
      t('OUTSIDER_ERP.ORDER.ITEMS_VALUE', {
        products: props.order.QtdProduto || 0,
        services: props.order.QtdServico || 0,
      }),
    ],
  ].filter(([, value]) => value)
);

const payload = extra => ({
  company: props.order.Empresa,
  code: props.order.CodigoOS,
  conversation_id: props.conversationId || undefined,
  ...extra,
});

const saveSubstatus = async () => {
  saving.value = 'SubStatus';
  try {
    const { data } = await ErpAPI.setSubstatus(
      payload({ value: substatus.value })
    );
    emit('updated', data.order);
    useAlert(t('OUTSIDER_ERP.ORDER.SAVED'));
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    saving.value = '';
  }
};

const saveField = async field => {
  saving.value = field;
  try {
    const { data } = await ErpAPI.setField(
      payload({ field, value: drafts.value[field] })
    );
    emit('updated', data.order);
    useAlert(t('OUTSIDER_ERP.ORDER.SAVED'));
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    saving.value = '';
  }
};
</script>

<template>
  <article
    class="flex flex-col gap-2 p-3 text-sm border rounded-xl border-n-weak bg-n-solid-1"
  >
    <button
      type="button"
      class="flex flex-col gap-1.5 text-left"
      :aria-expanded="open"
      @click="open = !open"
    >
      <div class="flex items-center justify-between w-full gap-2">
        <span
          class="flex items-center gap-1.5 font-medium whitespace-nowrap text-n-slate-12"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :class="dotClass(order.Cor)"
          />
          {{ t('OUTSIDER_ERP.ORDER.CODE', { code: order.CodigoOS }) }}
          <span class="text-xs font-normal text-n-slate-10">
            {{ order.Empresa }}
          </span>
        </span>
        <span
          class="min-w-0 px-2 py-0.5 text-xs rounded-full truncate"
          :class="substatusClass(order.SubStatus)"
          :title="order.SubStatus"
        >
          {{ order.SubStatus || t('OUTSIDER_ERP.ORDER.NO_SUBSTATUS') }}
        </span>
      </div>
      <span
        v-if="order.DescricaoMaquina"
        class="flex items-center gap-1.5 text-n-slate-11"
      >
        <Icon icon="i-lucide-forklift" class="size-3.5 shrink-0" />
        <span class="truncate">{{ order.DescricaoMaquina }}</span>
      </span>
      <span
        class="flex flex-wrap items-center text-xs gap-x-3 gap-y-1 text-n-slate-11"
      >
        <span v-if="order.TipoAtendimento">{{ order.TipoAtendimento }}</span>
        <span>
          {{
            t('OUTSIDER_ERP.ORDER.ENTRY', {
              date: formatDate(order.DataEntrada),
            })
          }}
        </span>
        <span
          v-if="order.DataPrevisao"
          :class="late ? 'text-n-ruby-11 font-medium' : ''"
        >
          {{
            late
              ? t('OUTSIDER_ERP.ORDER.LATE', {
                  date: formatDate(order.DataPrevisao),
                  days: order.DiasAtraso,
                })
              : t('OUTSIDER_ERP.ORDER.FORECAST', {
                  date: formatDate(order.DataPrevisao),
                })
          }}
        </span>
        <span v-if="order.NomeTecnico" class="flex items-center gap-1">
          <Icon icon="i-lucide-wrench" class="size-3" />
          {{ order.NomeTecnico }}
        </span>
      </span>
    </button>

    <div v-if="open" class="flex flex-col gap-3 pt-2 border-t border-n-weak">
      <p v-if="order.Nome" class="mb-0 text-xs font-medium text-n-slate-12">
        {{ order.Nome }}
        <span class="font-normal text-n-slate-10">
          ·
          {{
            t('OUTSIDER_ERP.ORDER.CUSTOMER_CODE', { code: order.CodigoCliente })
          }}
          <template v-if="order.Cidade">
            · {{ order.Cidade }}/{{ order.UF }}
          </template>
        </span>
      </p>
      <dl class="grid grid-cols-2 gap-x-3 gap-y-1.5 text-xs mb-0">
        <template v-for="[key, value] in details" :key="key">
          <div class="flex flex-col min-w-0">
            <dt class="text-n-slate-10">
              {{ t(`OUTSIDER_ERP.ORDER.DETAILS.${key}`) }}
            </dt>
            <dd class="mb-0 truncate text-n-slate-12" :title="value">
              {{ value }}
            </dd>
          </div>
        </template>
      </dl>
      <div v-if="order.Observacoes" class="flex flex-col gap-0.5 text-xs">
        <span class="text-n-slate-10">
          {{ t('OUTSIDER_ERP.FIELDS.OBSERVACOES') }}
        </span>
        <p class="mb-0 whitespace-pre-line text-n-slate-12">
          {{ order.Observacoes }}
        </p>
      </div>

      <template v-if="erpState.canEdit">
        <div class="flex flex-col gap-1">
          <label
            class="text-xs text-n-slate-10"
            :for="`erp-sub-${order.Empresa}-${order.CodigoOS}`"
          >
            {{ t('OUTSIDER_ERP.FIELDS.SUBSTATUS') }}
          </label>
          <div class="flex items-center gap-2">
            <select
              :id="`erp-sub-${order.Empresa}-${order.CodigoOS}`"
              v-model="substatus"
              class="!mb-0 h-8 flex-1 min-w-0 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
            >
              <option
                v-for="option in substatusOptions"
                :key="option"
                :value="option"
              >
                {{ option }}
              </option>
            </select>
            <Button
              type="button"
              size="sm"
              :label="t('OUTSIDER_ERP.ORDER.SAVE')"
              :disabled="substatus === (order.SubStatus || '')"
              :is-loading="saving === 'SubStatus'"
              @click="saveSubstatus"
            />
          </div>
        </div>
        <div
          v-for="field in erpState.fields"
          :key="field"
          class="flex flex-col gap-1"
        >
          <label
            class="text-xs text-n-slate-10"
            :for="`erp-${field}-${order.Empresa}-${order.CodigoOS}`"
          >
            {{ fieldLabel(field) }}
          </label>
          <textarea
            :id="`erp-${field}-${order.Empresa}-${order.CodigoOS}`"
            v-model="drafts[field]"
            rows="2"
            maxlength="4000"
            class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
          />
          <div class="flex justify-end">
            <Button
              type="button"
              size="xs"
              variant="faded"
              color="slate"
              :label="t('OUTSIDER_ERP.ORDER.SAVE')"
              :disabled="(drafts[field] ?? '') === (order[field] ?? '')"
              :is-loading="saving === field"
              @click="saveField(field)"
            />
          </div>
        </div>
        <p v-if="conversationId" class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.ORDER.NOTE_HINT') }}
        </p>
      </template>
      <template v-else>
        <div v-if="order.Defeitos" class="flex flex-col gap-0.5 text-xs">
          <span class="text-n-slate-10">{{
            t('OUTSIDER_ERP.FIELDS.DEFEITOS')
          }}</span>
          <p class="mb-0 whitespace-pre-line text-n-slate-12">
            {{ order.Defeitos }}
          </p>
        </div>
        <p v-if="erpState.writeEnabled" class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.ORDER.VIEW_ONLY') }}
        </p>
      </template>
    </div>
  </article>
</template>
