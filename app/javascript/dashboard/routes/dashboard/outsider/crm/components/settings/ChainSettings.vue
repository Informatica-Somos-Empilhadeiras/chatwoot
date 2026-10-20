<script setup>
// OUTSIDER: "repasse em sequência" (ver app/services/outsider/crm/lost_chain.rb). Liga a automação,
// escolhe as unidades e a ordem (setas), quem fica com o negócio na unidade seguinte (sem
// responsável para alguém pegar, ou rodízio entre os vendedores) e os motivos de perda que não
// repassam. O limite de encaminhamentos por cliente continua em Configurações > Geral.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  units: { type: Array, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();

const ASSIGN_OPTIONS = ['pool', 'rotation'];

const current = props.access.settings || {};
const chosen = current.chain_unit_ids || [];

// as escolhidas primeiro, na ordem salva (mesmo inativas: o repasse pula, mas a ordem volta quando
// a unidade for reativada); depois as outras unidades ativas
const rows = ref(
  [
    ...chosen
      .map(id => props.units.find(unit => unit.id === id))
      .filter(Boolean),
    ...props.units.filter(
      unit => unit.active !== false && !chosen.includes(unit.id)
    ),
  ].map(unit => ({
    id: unit.id,
    name: unit.name,
    inactive: unit.active === false,
    on: chosen.includes(unit.id),
  }))
);
const enabled = ref(Boolean(current.chain_enabled));
const assign = ref(current.chain_assign || 'pool');
const skipReasonIds = ref([...(current.chain_skip_reason_ids || [])]);
const lostReasons = ref([]);
const reasonsLoaded = ref(false);
const isSaving = ref(false);

const selectedIds = computed(() =>
  rows.value.filter(row => row.on).map(row => row.id)
);
const tooFew = computed(() => enabled.value && selectedIds.value.length < 2);

const move = (index, offset) => {
  const list = [...rows.value];
  const [row] = list.splice(index, 1);
  list.splice(index + offset, 0, row);
  rows.value = list;
};

const position = row => selectedIds.value.indexOf(row.id) + 1;

const toggleReason = (id, on) => {
  skipReasonIds.value = on
    ? [...skipReasonIds.value, id]
    : skipReasonIds.value.filter(item => item !== id);
};

const save = async () => {
  if (tooFew.value) return;
  isSaving.value = true;
  try {
    await CrmAPI.updateSettings({
      chain_enabled: enabled.value,
      chain_unit_ids: selectedIds.value,
      chain_assign: assign.value,
      // sem a lista de motivos carregada, mantém as exceções já salvas
      ...(reasonsLoaded.value && {
        chain_skip_reason_ids: skipReasonIds.value.filter(id =>
          lostReasons.value.some(reason => reason.id === id)
        ),
      }),
    });
    useAlert(t('OUTSIDER_CRM.SETTINGS.CHAIN.SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  try {
    const { data } = await CrmAPI.getLostReasons();
    lostReasons.value = data.filter(reason => reason.kind !== 'forward');
    reasonsLoaded.value = true;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
});
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.CHAIN.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.CHAIN.DESCRIPTION')"
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <div
        class="flex items-start gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <Switch v-model="enabled" class="mt-0.5" />
        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.ENABLE') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.ENABLE_HELP') }}
          </span>
        </div>
      </div>

      <div
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
        :class="{ 'opacity-60': !enabled }"
      >
        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.ORDER') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.ORDER_HELP') }}
          </span>
        </div>
        <ol class="flex flex-col gap-1.5 mb-0 list-none">
          <li
            v-for="(row, index) in rows"
            :key="row.id"
            class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-alpha-1"
          >
            <Checkbox v-model="row.on" />
            <span
              class="flex items-center justify-center text-xs font-medium rounded-full size-5 shrink-0"
              :class="
                row.on
                  ? 'bg-n-blue-3 text-n-blue-11'
                  : 'bg-n-alpha-2 text-n-slate-10'
              "
            >
              {{ row.on ? position(row) : '–' }}
            </span>
            <span
              class="flex-1 text-sm truncate"
              :class="row.on ? 'text-n-slate-12' : 'text-n-slate-10'"
            >
              {{ row.name }}
              <span v-if="row.inactive" class="text-xs text-n-slate-10">
                {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.INACTIVE') }}
              </span>
            </span>
            <Button
              type="button"
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-arrow-up"
              :title="t('OUTSIDER_CRM.SETTINGS.CHAIN.UP')"
              :disabled="index === 0"
              @click="move(index, -1)"
            />
            <Button
              type="button"
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-arrow-down"
              :title="t('OUTSIDER_CRM.SETTINGS.CHAIN.DOWN')"
              :disabled="index === rows.length - 1"
              @click="move(index, 1)"
            />
          </li>
        </ol>
        <p v-if="tooFew" class="mb-0 text-xs text-n-ruby-11">
          {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.NEED_UNITS') }}
        </p>
        <p class="flex items-center gap-1.5 mb-0 text-xs text-n-slate-11">
          <Icon icon="i-lucide-repeat" class="size-3.5 shrink-0" />
          {{
            t('OUTSIDER_CRM.SETTINGS.CHAIN.LIMIT', {
              max: access.settings?.max_forward_attempts ?? 3,
            })
          }}
        </p>
      </div>

      <div
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
        :class="{ 'opacity-60': !enabled }"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.ASSIGN') }}
        </span>
        <div class="grid gap-2 sm:grid-cols-2">
          <button
            v-for="option in ASSIGN_OPTIONS"
            :key="option"
            type="button"
            class="flex items-start gap-2 px-3 py-2 text-start rounded-lg outline outline-1 -outline-offset-1"
            :class="
              assign === option
                ? 'outline-n-blue-8 bg-n-blue-2'
                : 'outline-n-weak hover:bg-n-alpha-1'
            "
            @click="assign = option"
          >
            <Icon
              :icon="
                assign === option ? 'i-lucide-circle-check' : 'i-lucide-circle'
              "
              class="size-4 mt-0.5 shrink-0"
              :class="assign === option ? 'text-n-blue-11' : 'text-n-slate-9'"
            />
            <span class="flex flex-col gap-0.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{
                  t(
                    `OUTSIDER_CRM.SETTINGS.CHAIN.ASSIGN_${option.toUpperCase()}`
                  )
                }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  t(
                    `OUTSIDER_CRM.SETTINGS.CHAIN.ASSIGN_${option.toUpperCase()}_HELP`
                  )
                }}
              </span>
            </span>
          </button>
        </div>
      </div>

      <div
        v-if="lostReasons.length"
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
        :class="{ 'opacity-60': !enabled }"
      >
        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.SKIP') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.CHAIN.SKIP_HELP') }}
          </span>
        </div>
        <div class="flex flex-wrap gap-x-5 gap-y-2">
          <label
            v-for="reason in lostReasons"
            :key="reason.id"
            class="flex items-center gap-2 text-sm text-n-slate-12"
          >
            <Checkbox
              :model-value="skipReasonIds.includes(reason.id)"
              @update:model-value="on => toggleReason(reason.id, on)"
            />
            {{ reason.name }}
          </label>
        </div>
      </div>

      <div>
        <Button
          type="submit"
          size="sm"
          :label="t('OUTSIDER_CRM.SAVE')"
          :is-loading="isSaving"
          :disabled="tooFew"
        />
      </div>
    </form>
  </SettingsSection>
</template>
