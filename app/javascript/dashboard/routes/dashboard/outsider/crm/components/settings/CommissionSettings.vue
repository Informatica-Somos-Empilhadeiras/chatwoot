<script setup>
// OUTSIDER: percentuais de comissão (ver app/services/outsider/crm/commission.rb). Comissão = valor
// dos negócios ganhos no mês × percentual. Começa pelo percentual geral; os específicos (por
// vendedor, por unidade ou os dois) valem no lugar dele. A alteração vale a partir deste mês.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SettingsSection from './SettingsSection.vue';
import {
  bpToInput,
  errorMessage,
  formatMoney,
  formatMonth,
  formatPercent,
  percentToBp,
} from '../../helpers';

const props = defineProps({
  units: { type: Array, required: true },
});

const { t } = useI18n();

const MAX_RULES = 100;
const general = ref('');
const rules = ref([]);
const people = ref([]);
const from = ref(null);
const isLoading = ref(true);
const isSaving = ref(false);

const personOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.SETTINGS.COMMISSION.ANY_SELLER') },
  ...people.value.map(person => ({ value: person.id, label: person.name })),
]);
const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.SETTINGS.COMMISSION.ANY_UNIT') },
  ...props.units.map(unit => ({ value: unit.id, label: unit.name })),
]);

const generalBp = computed(() => percentToBp(general.value));
const example = computed(() =>
  Number.isNaN(generalBp.value)
    ? ''
    : t('OUTSIDER_CRM.SETTINGS.COMMISSION.EXAMPLE', {
        percent: formatPercent(generalBp.value),
        value: formatMoney(Math.round((100000 * generalBp.value) / 10000)),
      })
);

const ruleKey = rule => `${rule.user_id || ''}-${rule.business_unit_id || ''}`;
const duplicated = computed(() => {
  const keys = rules.value.map(ruleKey);
  return keys.filter((key, index) => keys.indexOf(key) !== index);
});

const ruleError = rule => {
  if (!rule.user_id && !rule.business_unit_id) {
    return t('OUTSIDER_CRM.SETTINGS.COMMISSION.ERRORS.TARGET');
  }
  if (Number.isNaN(percentToBp(rule.percent)) || rule.percent === '') {
    return t('OUTSIDER_CRM.SETTINGS.COMMISSION.ERRORS.PERCENT');
  }
  if (duplicated.value.includes(ruleKey(rule))) {
    return t('OUTSIDER_CRM.SETTINGS.COMMISSION.ERRORS.DUPLICATE');
  }
  return '';
};

const isValid = computed(
  () =>
    !Number.isNaN(generalBp.value) &&
    rules.value.every(rule => !ruleError(rule))
);

const apply = data => {
  from.value = data.from;
  people.value = data.people;
  general.value = bpToInput(data.general_bp);
  rules.value = data.rules.map(rule => ({
    user_id: rule.user_id || '',
    business_unit_id: rule.business_unit_id || '',
    percent: bpToInput(rule.bp) || '0',
  }));
};

const load = async () => {
  try {
    const { data } = await CrmAPI.getCommission();
    apply(data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const addRule = () => {
  if (rules.value.length < MAX_RULES) {
    rules.value.push({ user_id: '', business_unit_id: '', percent: '' });
  }
};

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateCommission(
      generalBp.value,
      rules.value.map(rule => ({
        user_id: rule.user_id || null,
        business_unit_id: rule.business_unit_id || null,
        bp: percentToBp(rule.percent),
      }))
    );
    apply(data);
    useAlert(t('OUTSIDER_CRM.SETTINGS.COMMISSION.SAVED'));
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

onMounted(load);
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.COMMISSION.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.COMMISSION.DESCRIPTION')"
  >
    <template #actions>
      <Button
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isValid || isLoading"
        @click="save"
      />
    </template>

    <section class="flex flex-col gap-2 p-4 rounded-xl bg-n-alpha-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.SETTINGS.COMMISSION.GENERAL') }}
      </span>
      <div class="flex flex-wrap items-center gap-3">
        <Input
          v-model="general"
          inputmode="decimal"
          class="w-32"
          :placeholder="
            t('OUTSIDER_CRM.SETTINGS.COMMISSION.PERCENT_PLACEHOLDER')
          "
        />
        <span class="text-sm text-n-slate-11">%</span>
        <span class="text-xs text-n-slate-11">{{ example }}</span>
      </div>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.SETTINGS.COMMISSION.GENERAL_HELP') }}
      </p>
    </section>

    <section class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.SETTINGS.COMMISSION.SPECIFIC') }}
        </span>
        <Button
          icon="i-lucide-plus"
          size="xs"
          variant="ghost"
          :label="t('OUTSIDER_CRM.SETTINGS.COMMISSION.ADD')"
          @click="addRule"
        />
      </div>
      <p
        v-if="!rules.length"
        class="p-4 mb-0 text-sm text-center rounded-xl bg-n-solid-2 text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-container"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.COMMISSION.NO_SPECIFIC') }}
      </p>
      <div
        v-else
        class="overflow-hidden rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <div
          v-for="(rule, index) in rules"
          :key="index"
          class="flex flex-col gap-1 px-4 py-3 border-b border-n-weak last:border-0"
        >
          <div class="flex flex-wrap items-center gap-2">
            <Select v-model="rule.user_id" :options="personOptions" />
            <Select v-model="rule.business_unit_id" :options="unitOptions" />
            <Input
              v-model="rule.percent"
              inputmode="decimal"
              class="w-24"
              :placeholder="
                t('OUTSIDER_CRM.SETTINGS.COMMISSION.PERCENT_PLACEHOLDER')
              "
            />
            <span class="text-sm text-n-slate-11">%</span>
            <div class="flex-1" />
            <Button
              icon="i-lucide-trash-2"
              size="xs"
              variant="ghost"
              color="ruby"
              :aria-label="t('OUTSIDER_CRM.SETTINGS.COMMISSION.REMOVE')"
              @click="rules.splice(index, 1)"
            />
          </div>
          <span v-if="ruleError(rule)" class="text-xs text-n-ruby-11">
            {{ ruleError(rule) }}
          </span>
        </div>
      </div>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.SETTINGS.COMMISSION.ORDER') }}
      </p>
    </section>

    <p class="mb-0 text-xs text-n-slate-11">
      {{
        from
          ? t('OUTSIDER_CRM.SETTINGS.COMMISSION.SINCE', {
              month: formatMonth(from),
            })
          : t('OUTSIDER_CRM.SETTINGS.COMMISSION.NEVER')
      }}
      {{ t('OUTSIDER_CRM.SETTINGS.COMMISSION.MONTHS') }}
    </p>
  </SettingsSection>
</template>
