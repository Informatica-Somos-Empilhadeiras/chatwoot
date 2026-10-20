<script setup>
// OUTSIDER: confirmação de "Encaminhar para outra unidade". Mostra origem e destino, a tentativa
// contra o limite da conta e as unidades onde não dá para encaminhar (com o motivo). Ao confirmar,
// a origem fecha como encaminhada e o negócio continua na unidade escolhida (OpportunityForwarder).
// Nada é enviado ao cliente.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import LoadError from '../activity/LoadError.vue';
import { errorMessage, formatMoney } from '../helpers';

defineProps({
  // nome da unidade de origem (a tela que abre já sabe; o servidor não repete)
  unitName: { type: String, default: '' },
});

const emit = defineEmits(['forwarded']);

const { t } = useI18n();

const NOTES_LIMIT = 2000;

const dialogRef = ref(null);
const opportunity = ref(null);
const options = ref(null);
const loadError = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const form = ref({});

const units = computed(() => options.value?.units || []);
const selectedUnit = computed(() =>
  units.value.find(unit => unit.id === form.value.to_business_unit_id)
);
const owner = computed(() =>
  selectedUnit.value?.members.find(member => member.id === form.value.owner_id)
);
const attempts = computed(() => options.value?.attempts);
const conversation = computed(() => options.value?.conversation);
const limitReached = computed(() => !!attempts.value?.limit_reached);
const nothingAvailable = computed(
  () => !!options.value && !units.value.some(unit => unit.available)
);

const pipelineOptions = computed(() =>
  (selectedUnit.value?.pipelines || []).map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);

const roleLabel = role =>
  t(`OUTSIDER_CRM.FORWARD.ROLES.${String(role).toUpperCase()}`);

const ownerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FORWARD.NO_OWNER') },
  ...(selectedUnit.value?.members || []).map(member => ({
    value: member.id,
    label: `${member.name} · ${roleLabel(member.role)}`,
  })),
]);

const reasonOptions = computed(() =>
  (options.value?.reasons || []).map(reason => ({
    value: reason.id,
    label: reason.name,
  }))
);

// atribuir a conversa só quando o responsável e quem encaminha estão na caixa de entrada dela
const assignBlocker = computed(() => {
  if (!conversation.value) return '';
  if (!owner.value) return t('OUTSIDER_CRM.FORWARD.ASSIGN_NEEDS_OWNER');
  if (!owner.value.in_inbox) {
    return t('OUTSIDER_CRM.FORWARD.ASSIGN_NOT_IN_INBOX', {
      name: owner.value.name,
      inbox: conversation.value.inbox_name,
    });
  }
  if (!conversation.value.can_assign) {
    return t('OUTSIDER_CRM.FORWARD.ASSIGN_FORBIDDEN', {
      inbox: conversation.value.inbox_name,
    });
  }
  return '';
});

const isValid = computed(
  () =>
    !!selectedUnit.value?.available &&
    !limitReached.value &&
    (!options.value?.reason_required || !!form.value.reason_id) &&
    (form.value.notes || '').length <= NOTES_LIMIT
);

const unitHint = unit => {
  if (unit.unavailable_reason === 'open_opportunity') {
    return t('OUTSIDER_CRM.FORWARD.UNIT_HAS_OPEN', {
      code: unit.open_opportunity_code,
    });
  }
  if (unit.unavailable_reason === 'no_pipeline') {
    return t('OUTSIDER_CRM.FORWARD.UNIT_NO_PIPELINE');
  }
  return t('OUTSIDER_CRM.FORWARD.UNIT_MEMBERS', {
    count: unit.members.length,
  });
};

// sugestão de responsável: o primeiro gestor da unidade (a lista vem com gestores primeiro)
const defaultOwner = unit =>
  unit?.members.find(member => member.role !== 'administrator')?.id || '';

const selectUnit = unit => {
  if (!unit.available || limitReached.value) return;
  form.value.to_business_unit_id = unit.id;
  form.value.pipeline_id = unit.pipelines[0]?.id || '';
  form.value.owner_id = defaultOwner(unit);
};

watch(
  () => form.value.owner_id,
  () => {
    form.value.create_task = !!form.value.owner_id;
    if (assignBlocker.value) form.value.assign_conversation = false;
  }
);

const loadOptions = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.getForwardOptions(opportunity.value.id);
    options.value = data;
    const available = data.units.filter(unit => unit.available);
    if (available.length === 1) selectUnit(available[0]);
  } catch (error) {
    loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
  }
};

const open = item => {
  opportunity.value = item;
  options.value = null;
  form.value = {
    to_business_unit_id: null,
    pipeline_id: '',
    owner_id: '',
    reason_id: '',
    notes: '',
    create_task: false,
    complete_tasks: true,
    assign_conversation: false,
  };
  dialogRef.value?.open();
  loadOptions();
};

const confirm = async () => {
  if (!isValid.value || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.forwardOpportunity(opportunity.value.id, {
      ...form.value,
      pipeline_id: form.value.pipeline_id || null,
      owner_id: form.value.owner_id || null,
      reason_id: form.value.reason_id || null,
      create_task: form.value.create_task && !!form.value.owner_id,
      complete_tasks:
        form.value.complete_tasks && !!options.value.pending_tasks,
      assign_conversation:
        form.value.assign_conversation && !assignBlocker.value,
    });
    useAlert(
      t('OUTSIDER_CRM.FORWARD.DONE', {
        code: opportunity.value.code,
        unit: selectedUnit.value.name,
      })
    );
    dialogRef.value?.close();
    emit('forwarded', data);
  } catch (error) {
    useAlert(errorMessage(t, error));
    // a situação pode ter mudado (outra pessoa encaminhou, limite, negócio aberto no destino)
    if (error?.response?.status === 422) loadOptions();
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="t('OUTSIDER_CRM.FORWARD.TITLE')"
    :confirm-button-label="t('OUTSIDER_CRM.FORWARD.CONFIRM')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    @confirm="confirm"
  >
    <template #description>
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          t('OUTSIDER_CRM.FORWARD.DESCRIPTION', {
            code: opportunity?.code,
          })
        }}
      </p>
    </template>

    <div class="flex flex-col gap-4">
      <div class="grid items-stretch grid-cols-[1fr_auto_1fr] gap-2">
        <div class="flex flex-col min-w-0 gap-0.5 p-3 rounded-lg bg-n-alpha-1">
          <span class="text-xs font-medium uppercase text-n-slate-10">
            {{ t('OUTSIDER_CRM.FORWARD.ORIGIN') }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ unitName || '—' }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{ opportunity?.code }} · {{ opportunity?.title }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ formatMoney(opportunity?.value_cents) }}
          </span>
        </div>
        <span class="flex items-center text-n-slate-9">
          <Icon icon="i-lucide-arrow-right" class="size-4" />
        </span>
        <div
          class="flex flex-col min-w-0 gap-0.5 p-3 rounded-lg"
          :class="
            selectedUnit
              ? 'bg-n-blue-2 outline outline-1 -outline-offset-1 outline-n-blue-6'
              : 'bg-n-alpha-1'
          "
        >
          <span class="text-xs font-medium uppercase text-n-slate-10">
            {{ t('OUTSIDER_CRM.FORWARD.DESTINATION') }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ selectedUnit?.name || t('OUTSIDER_CRM.FORWARD.CHOOSE_UNIT') }}
          </span>
          <span v-if="owner" class="text-xs truncate text-n-slate-11">
            {{ t('OUTSIDER_CRM.FORWARD.OWNER_SHORT', { name: owner.name }) }}
          </span>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center p-4 text-n-slate-10">
        <Spinner :size="18" />
      </div>

      <LoadError
        v-else-if="loadError"
        :message="loadError"
        @retry="loadOptions"
      />

      <template v-else-if="options">
        <p
          class="flex items-center gap-2 px-3 py-2 mb-0 text-sm rounded-lg"
          :class="
            limitReached
              ? 'bg-n-ruby-2 text-n-ruby-11'
              : 'bg-n-amber-2 text-n-amber-11'
          "
        >
          <Icon
            :icon="limitReached ? 'i-lucide-octagon-alert' : 'i-lucide-repeat'"
            class="size-4 shrink-0"
          />
          {{
            limitReached
              ? t('OUTSIDER_CRM.FORWARD.LIMIT_REACHED', { max: attempts.max })
              : t('OUTSIDER_CRM.FORWARD.ATTEMPT', {
                  current: attempts.next,
                  max: attempts.max,
                })
          }}
        </p>

        <template v-if="!limitReached">
          <div class="flex flex-col gap-1.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.FORWARD.UNIT') }}
            </span>
            <p v-if="!units.length" class="mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_CRM.FORWARD.NO_UNITS') }}
            </p>
            <div class="grid gap-2 sm:grid-cols-2">
              <button
                v-for="unit in units"
                :key="unit.id"
                type="button"
                class="flex flex-col gap-0.5 px-3 py-2 text-start rounded-lg outline outline-1 -outline-offset-1"
                :class="[
                  unit.id === form.to_business_unit_id
                    ? 'outline-n-blue-8 bg-n-blue-2'
                    : 'outline-n-weak',
                  unit.available
                    ? 'hover:bg-n-alpha-1'
                    : 'opacity-60 cursor-not-allowed',
                ]"
                :disabled="!unit.available"
                @click="selectUnit(unit)"
              >
                <span
                  class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
                >
                  <Icon
                    :icon="
                      unit.id === form.to_business_unit_id
                        ? 'i-lucide-circle-check'
                        : 'i-lucide-building-2'
                    "
                    class="size-4 shrink-0"
                    :class="
                      unit.id === form.to_business_unit_id
                        ? 'text-n-blue-11'
                        : 'text-n-slate-10'
                    "
                  />
                  <span class="truncate">{{ unit.name }}</span>
                </span>
                <span
                  class="text-xs"
                  :class="unit.available ? 'text-n-slate-11' : 'text-n-ruby-11'"
                >
                  {{ unitHint(unit) }}
                </span>
              </button>
            </div>
            <p
              v-if="nothingAvailable && units.length"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{ t('OUTSIDER_CRM.FORWARD.NOTHING_AVAILABLE') }}
            </p>
          </div>

          <template v-if="selectedUnit">
            <div class="grid gap-3 sm:grid-cols-2">
              <label
                v-if="pipelineOptions.length > 1"
                class="flex flex-col gap-1"
              >
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('OUTSIDER_CRM.OPPORTUNITY.PIPELINE') }}
                </span>
                <Select
                  v-model="form.pipeline_id"
                  :options="pipelineOptions"
                  class="!w-full [&>select]:w-full"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('OUTSIDER_CRM.FORWARD.OWNER') }}
                </span>
                <Select
                  v-model="form.owner_id"
                  :options="ownerOptions"
                  class="!w-full [&>select]:w-full"
                />
              </label>
              <label v-if="reasonOptions.length" class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{
                    options.reason_required
                      ? t('OUTSIDER_CRM.FORWARD.REASON_REQUIRED')
                      : t('OUTSIDER_CRM.FORWARD.REASON')
                  }}
                </span>
                <Select
                  v-model="form.reason_id"
                  :options="reasonOptions"
                  :placeholder="t('OUTSIDER_CRM.BOARD.CHOOSE_REASON')"
                  class="!w-full [&>select]:w-full"
                />
              </label>
            </div>

            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('OUTSIDER_CRM.FORWARD.NOTES') }}
              </span>
              <textarea
                v-model="form.notes"
                rows="3"
                :maxlength="NOTES_LIMIT"
                class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-blue-8"
                :placeholder="t('OUTSIDER_CRM.FORWARD.NOTES_PLACEHOLDER')"
              />
            </label>

            <div class="flex flex-col gap-2 text-sm text-n-slate-12">
              <label
                class="flex items-start gap-2"
                :class="{ 'opacity-60': !form.owner_id }"
              >
                <Checkbox
                  v-model="form.create_task"
                  :disabled="!form.owner_id"
                  class="mt-0.5 shrink-0"
                />
                <span>
                  {{
                    owner
                      ? t('OUTSIDER_CRM.FORWARD.CREATE_TASK', {
                          name: owner.name,
                        })
                      : t('OUTSIDER_CRM.FORWARD.CREATE_TASK_NO_OWNER')
                  }}
                </span>
              </label>
              <label
                v-if="options.pending_tasks"
                class="flex items-start gap-2"
              >
                <Checkbox
                  v-model="form.complete_tasks"
                  class="mt-0.5 shrink-0"
                />
                <span>
                  {{
                    t('OUTSIDER_CRM.FORWARD.COMPLETE_TASKS', {
                      count: options.pending_tasks,
                    })
                  }}
                </span>
              </label>
              <label
                v-if="conversation"
                class="flex items-start gap-2"
                :class="{ 'opacity-60': assignBlocker }"
              >
                <Checkbox
                  v-model="form.assign_conversation"
                  :disabled="!!assignBlocker"
                  class="mt-0.5 shrink-0"
                />
                <span class="flex flex-col">
                  <span>
                    {{
                      t('OUTSIDER_CRM.FORWARD.ASSIGN_CONVERSATION', {
                        id: conversation.display_id,
                        name: owner?.name || '—',
                      })
                    }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{
                      assignBlocker ||
                      (conversation.assignee
                        ? t('OUTSIDER_CRM.FORWARD.ASSIGNED_NOW', {
                            name: conversation.assignee.name,
                          })
                        : t('OUTSIDER_CRM.FORWARD.UNASSIGNED_NOW'))
                    }}
                  </span>
                </span>
              </label>
            </div>
          </template>
        </template>

        <p class="flex items-center gap-1.5 mb-0 text-xs text-n-slate-10">
          <Icon icon="i-lucide-shield-check" class="size-3.5 shrink-0" />
          {{ t('OUTSIDER_CRM.FORWARD.NO_CUSTOMER_MESSAGE') }}
        </p>
      </template>
    </div>
  </Dialog>
</template>
