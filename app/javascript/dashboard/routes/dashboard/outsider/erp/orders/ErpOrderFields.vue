<script setup>
// OUTSIDER: os campos da OS feita no chat, os mesmos que o desktop pede: máquina (+ horímetro), tipo de atendimento,
// previsão, entrega, classe e máquina normal/parada (o técnico e o envio para o app ficam só no Agendar); na Nova OS também defeitos e observações (na conversão o
// desktop grava defeitos "." e copia as observações do orçamento). Quem salva é a tela que usa (gaveta ou conversão).
// compact: a tela de converter (duas colunas). Slot "customer": o cartão do cliente, ao lado da máquina.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpOrderMachine from './ErpOrderMachine.vue';

const props = defineProps({
  company: { type: String, required: true },
  customer: { type: [Number, String], default: null },
  options: { type: Object, default: () => ({}) },
  kind: { type: String, default: 'fresh' },
  compact: { type: Boolean, default: false },
  readOnly: { type: Boolean, default: false },
  // o que falta (o primeiro motivo do rodapé): o campo fica em vermelho
  missing: { type: String, default: '' },
  // a conversão avisa que o orçamento nunca traz máquina
  machineNote: { type: String, default: '' },
});

const fields = defineModel({ type: Object, default: () => ({}) });

const { t } = useI18n();
const lastHours = ref('');

const set = (key, value) => {
  fields.value = { ...fields.value, [key]: value };
};

const machine = computed({
  get: () => ({
    maquina: fields.value.maquina,
    maquina_descricao: fields.value.maquina_descricao,
    serie: fields.value.serie,
    maquina_do_cliente: fields.value.maquina_do_cliente,
  }),
  set: value => {
    fields.value = { ...fields.value, ...value };
  },
});

const types = computed(() => {
  const list = props.options.attendance_types || [];
  const current = fields.value.tipo_atendimento;
  return current && !list.includes(current) ? [current, ...list] : list;
});
const classes = computed(() => props.options.classes || []);
const machineRequired = computed(() => props.options.machine_required === true);

const INPUT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand disabled:opacity-70 normal-case';
const SELECT = `${INPUT} !pr-7 bg-[right_-1.25rem_center]`;
const AREA =
  '!mb-0 w-full min-h-[4.5rem] px-2.5 py-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand disabled:opacity-70 normal-case resize-y';
const LABEL =
  'flex flex-col gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10';
const bad = key => props.missing === key && '!outline-n-ruby-9';
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      class="grid gap-3"
      :class="
        compact
          ? 'sm:grid-cols-[minmax(0,3fr)_minmax(0,1fr)]'
          : 'md:grid-cols-[minmax(0,5fr)_minmax(0,5fr)_minmax(0,2fr)]'
      "
    >
      <slot name="customer" />
      <div :class="LABEL">
        <span>
          {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE') }}
          <span v-if="machineRequired" class="text-n-ruby-11">*</span>
          <span v-if="machineNote" class="normal-case text-n-amber-11">
            · {{ machineNote }}
          </span>
        </span>
        <ErpOrderMachine
          v-model="machine"
          :company="company"
          :customer="customer"
          :kind="kind"
          :required="machineRequired"
          :disabled="readOnly || !customer"
          :invalid="['maquina_obrigatoria', 'maquina'].includes(missing)"
          @last-hours="value => (lastHours = value)"
        />
      </div>
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.HOURS') }}
        <input
          :value="fields.horimetro"
          maxlength="7"
          inputmode="decimal"
          :placeholder="
            lastHours
              ? t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.LAST_HOURS', {
                  value: lastHours,
                })
              : ''
          "
          :disabled="readOnly"
          :class="INPUT"
          @input="set('horimetro', $event.target.value)"
        />
      </label>
    </div>

    <div
      class="grid gap-3"
      :class="
        compact
          ? 'grid-cols-2'
          : 'grid-cols-2 md:grid-cols-3 xl:grid-cols-[minmax(0,1.8fr)_minmax(0,1.6fr)_minmax(0,1.3fr)_minmax(0,1.4fr)_auto]'
      "
    >
      <label :class="LABEL">
        <span>
          {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.TYPE') }}
          <span class="text-n-ruby-11">*</span>
        </span>
        <select
          :value="fields.tipo_atendimento || ''"
          :disabled="readOnly"
          :class="[SELECT, bad('tipo_atendimento')]"
          data-erp-order-type
          @change="set('tipo_atendimento', $event.target.value || null)"
        >
          <option value="" disabled>
            {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.TYPE_PICK') }}
          </option>
          <option v-for="name in types" :key="name" :value="name">
            {{ name }}
          </option>
        </select>
      </label>
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.FORECAST') }}
        <input
          type="datetime-local"
          :value="fields.previsao || ''"
          :disabled="readOnly"
          :class="INPUT"
          @change="set('previsao', $event.target.value || null)"
        />
      </label>
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.DELIVERY') }}
        <input
          type="date"
          :value="fields.entrega || ''"
          :disabled="readOnly"
          :class="INPUT"
          @change="set('entrega', $event.target.value || null)"
        />
      </label>
      <label :class="LABEL">
        <span>
          {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.CLASS') }}
          <span class="text-n-ruby-11">*</span>
        </span>
        <select
          :value="fields.classe ? String(fields.classe) : ''"
          :disabled="readOnly"
          :class="[SELECT, bad('classe')]"
          data-erp-order-class
          @change="set('classe', Number($event.target.value) || null)"
        >
          <option value="" disabled>
            {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.CLASS_PICK') }}
          </option>
          <option
            v-for="item in classes"
            :key="item.codigo"
            :value="String(item.codigo)"
          >
            {{ item.descricao }}
          </option>
        </select>
      </label>
      <div :class="LABEL">
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.MACHINE_STATE') }}
        <div
          class="inline-flex h-9 overflow-hidden rounded-lg outline outline-1 -outline-offset-1 outline-n-slate-6"
          role="group"
        >
          <button
            v-for="stopped in [false, true]"
            :key="String(stopped)"
            type="button"
            class="flex-1 px-3 text-sm normal-case disabled:opacity-70"
            :class="
              (fields.maquina_parada === true) === stopped
                ? stopped
                  ? 'bg-n-ruby-3 text-n-ruby-11 font-medium'
                  : 'bg-n-teal-3 text-n-teal-11 font-medium'
                : 'bg-n-solid-1 text-n-slate-11'
            "
            :aria-pressed="(fields.maquina_parada === true) === stopped"
            :disabled="readOnly"
            @click="set('maquina_parada', stopped)"
          >
            {{
              stopped
                ? t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.STOPPED')
                : t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.NORMAL')
            }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="!compact" class="grid gap-3 md:grid-cols-2">
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.DEFECTS') }}
        <textarea
          :value="fields.defeitos || ''"
          maxlength="5000"
          rows="3"
          :placeholder="
            t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.DEFECTS_PLACEHOLDER')
          "
          :disabled="readOnly"
          :class="AREA"
          @input="set('defeitos', $event.target.value)"
        />
      </label>
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.NOTES') }}
        <textarea
          :value="fields.observacoes || ''"
          maxlength="5000"
          rows="3"
          :placeholder="t('OUTSIDER_ERP.ORDER_DRAFT.FIELDS.NOTES_PLACEHOLDER')"
          :disabled="readOnly"
          :class="AREA"
          @input="set('observacoes', $event.target.value)"
        />
      </label>
    </div>
  </div>
</template>
