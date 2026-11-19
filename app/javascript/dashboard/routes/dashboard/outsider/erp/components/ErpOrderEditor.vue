<script setup>
// OUTSIDER: controles de edição de uma OS do ERP (só para quem pode editar: escrita ligada + perfil "Usa"). Cada
// gravação vai direto para o ERP (Outsider::Erp::Writer) e, numa conversa, deixa uma nota privada do que mudou.
// Fica separado do cartão (ErpOrderCard) para o cartão só exibir. Situação, tipo de atendimento e técnico usam as
// listas do próprio ERP; os demais campos liberados nas Configurações entram como texto ou data (AAAA-MM-DD).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  erpState,
  erpLists,
  loadErpLists,
  erpErrorMessage,
  toDateInput,
} from '../erpStore';

const props = defineProps({
  order: { type: Object, required: true },
  options: { type: Array, default: () => [] },
  conversationId: { type: [Number, String], default: null },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const substatus = ref(props.order.SubStatus || '');
const situacao = ref(props.order.Situacao || '');
const atendimento = ref(props.order.TipoAtendimento || '');
const tecnico = ref(String(props.order.TecnicoAtual || ''));
const drafts = ref({});
const saving = ref('');

const isDate = field => erpState.fieldKinds[field] === 'date';
// valor atual do campo como o controle mostra (data em AAAA-MM-DD, no dia de Brasília)
const original = field =>
  isDate(field) ? toDateInput(props.order[field]) : (props.order[field] ?? '');

const resetDrafts = () => {
  substatus.value = props.order.SubStatus || '';
  situacao.value = props.order.Situacao || '';
  atendimento.value = props.order.TipoAtendimento || '';
  tecnico.value = String(props.order.TecnicoAtual || '');
  drafts.value = Object.fromEntries(
    erpState.fields.map(field => [field, original(field)])
  );
};
watch(() => props.order, resetDrafts, { immediate: true });

onMounted(() => {
  if (erpState.canEdit) loadErpLists();
});

const id = suffix =>
  `erp-${suffix}-${props.order.Empresa}-${props.order.CodigoOS}`;

const fieldLabel = field => {
  const key = `OUTSIDER_ERP.FIELDS.${field.toUpperCase()}`;
  const label = t(key);
  return label === key ? field : label;
};

// a opção atual entra na lista mesmo se não vier do ERP, para não "sumir" o valor que a OS já tem
const withCurrent = (list, current) =>
  current && !list.includes(current) ? [current, ...list] : list;
const substatusOptions = computed(() =>
  withCurrent(props.options, props.order.SubStatus)
);
const statusOptions = computed(() =>
  withCurrent(erpLists.statuses, props.order.Situacao)
);
const attendanceOptions = computed(() =>
  withCurrent(erpLists.attendanceTypes, props.order.TipoAtendimento)
);
const currentTecnicoName = computed(
  () => props.order.NomeTecnico || t('OUTSIDER_ERP.ORDER.NO_TECHNICIAN')
);

const payload = extra => ({
  company: props.order.Empresa,
  code: props.order.CodigoOS,
  conversation_id: props.conversationId || undefined,
  ...extra,
});

const run = async (key, request) => {
  saving.value = key;
  try {
    const { data } = await request();
    emit('updated', data.order);
    useAlert(t('OUTSIDER_ERP.ORDER.SAVED'));
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    saving.value = '';
  }
};

const saveSubstatus = () =>
  run('SubStatus', () =>
    ErpAPI.setSubstatus(payload({ value: substatus.value }))
  );
const saveStatus = () =>
  run('Situacao', () => ErpAPI.setStatus(payload({ value: situacao.value })));
const saveAttendance = () =>
  run('TipoAtendimento', () =>
    ErpAPI.setAttendanceType(payload({ value: atendimento.value }))
  );
const saveTechnician = () => {
  const found = erpLists.technicians.find(
    item => String(item.codigo) === tecnico.value
  );
  return run('Tecnico', () =>
    ErpAPI.setTechnician(
      payload({ tecnico_id: tecnico.value, tecnico_name: found?.nome })
    )
  );
};
const saveField = field =>
  run(field, () =>
    ErpAPI.setField(payload({ field, value: drafts.value[field] }))
  );

const selectClass =
  '!mb-0 h-8 flex-1 min-w-0 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak';
</script>

<template>
  <div class="flex flex-col gap-3">
    <!-- Substatus -->
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-10" :for="id('sub')">
        {{ t('OUTSIDER_ERP.FIELDS.SUBSTATUS') }}
      </label>
      <div class="flex items-center gap-2">
        <select :id="id('sub')" v-model="substatus" :class="selectClass">
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

    <!-- Situação (status) -->
    <div v-if="erpLists.statuses.length" class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-10" :for="id('situacao')">
        {{ t('OUTSIDER_ERP.ORDER.DETAILS.SITUATION') }}
      </label>
      <div class="flex items-center gap-2">
        <select :id="id('situacao')" v-model="situacao" :class="selectClass">
          <option v-for="option in statusOptions" :key="option" :value="option">
            {{ option }}
          </option>
        </select>
        <Button
          type="button"
          size="sm"
          :label="t('OUTSIDER_ERP.ORDER.SAVE')"
          :disabled="situacao === (order.Situacao || '')"
          :is-loading="saving === 'Situacao'"
          @click="saveStatus"
        />
      </div>
    </div>

    <!-- Tipo de atendimento -->
    <div v-if="erpLists.attendanceTypes.length" class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-10" :for="id('atendimento')">
        {{ t('OUTSIDER_ERP.ORDER.DETAILS.SERVICE') }}
      </label>
      <div class="flex items-center gap-2">
        <select
          :id="id('atendimento')"
          v-model="atendimento"
          :class="selectClass"
        >
          <option
            v-for="option in attendanceOptions"
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
          :disabled="atendimento === (order.TipoAtendimento || '')"
          :is-loading="saving === 'TipoAtendimento'"
          @click="saveAttendance"
        />
      </div>
    </div>

    <!-- Técnico -->
    <div v-if="erpLists.technicians.length" class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-10" :for="id('tecnico')">
        {{ t('OUTSIDER_ERP.ORDER.DETAILS.TECHNICIAN') }}
      </label>
      <div class="flex items-center gap-2">
        <select :id="id('tecnico')" v-model="tecnico" :class="selectClass">
          <option value="">{{ currentTecnicoName }}</option>
          <option
            v-for="item in erpLists.technicians"
            :key="item.codigo"
            :value="String(item.codigo)"
          >
            {{ item.nome }}
          </option>
        </select>
        <Button
          type="button"
          size="sm"
          :label="t('OUTSIDER_ERP.ORDER.SAVE')"
          :disabled="!tecnico || tecnico === String(order.TecnicoAtual || '')"
          :is-loading="saving === 'Tecnico'"
          @click="saveTechnician"
        />
      </div>
    </div>

    <!-- Campos liberados nas Configurações (texto ou data) -->
    <div
      v-for="field in erpState.fields"
      :key="field"
      class="flex flex-col gap-1"
    >
      <label class="text-xs text-n-slate-10" :for="id(field)">
        {{ fieldLabel(field) }}
      </label>
      <input
        v-if="isDate(field)"
        :id="id(field)"
        v-model="drafts[field]"
        type="date"
        :class="selectClass"
      />
      <textarea
        v-else
        :id="id(field)"
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
          :disabled="(drafts[field] ?? '') === original(field)"
          :is-loading="saving === field"
          @click="saveField(field)"
        />
      </div>
    </div>

    <p v-if="conversationId" class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_ERP.ORDER.NOTE_HINT') }}
    </p>
  </div>
</template>
