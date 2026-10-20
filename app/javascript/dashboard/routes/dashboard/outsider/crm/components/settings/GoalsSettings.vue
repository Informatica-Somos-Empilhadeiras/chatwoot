<script setup>
// OUTSIDER: metas mensais de venda por unidade e por vendedor (ver app/services/outsider/crm/goals.rb).
// A meta gravada para um mês vale para ele e os seguintes, até a próxima alteração; vazio = sem meta.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SettingsSection from './SettingsSection.vue';
import {
  centsToInput,
  currentMonth,
  errorMessage,
  formatMoney,
  formatMonth,
  parseMoney,
  shiftMonth,
} from '../../helpers';

const props = defineProps({
  units: { type: Array, required: true },
});

const { t } = useI18n();

const month = ref(currentMonth());
const from = ref(null);
const people = ref([]);
const unitValues = ref({});
const userValues = ref({});
const isLoading = ref(true);
const isSaving = ref(false);

const activeUnits = computed(() => props.units.filter(unit => unit.active));

const toInputs = map =>
  Object.fromEntries(
    Object.entries(map || {}).map(([id, cents]) => [id, centsToInput(cents)])
  );

const toCents = values =>
  Object.fromEntries(
    Object.entries(values)
      .map(([id, text]) => [id, Math.round(parseMoney(text) * 100)])
      .filter(([, cents]) => cents)
  );

const isValid = computed(() =>
  [
    ...Object.values(unitValues.value),
    ...Object.values(userValues.value),
  ].every(text => {
    const value = parseMoney(text);
    return !Number.isNaN(value) && value >= 0;
  })
);

const unitTotal = computed(() =>
  Object.values(toCents(unitValues.value)).reduce(
    (sum, cents) => sum + cents,
    0
  )
);

const apply = data => {
  from.value = data.from;
  people.value = data.people;
  unitValues.value = toInputs(data.units);
  userValues.value = toInputs(data.users);
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getGoals(month.value);
    apply(data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateGoals(
      month.value,
      toCents(unitValues.value),
      toCents(userValues.value)
    );
    apply(data);
    useAlert(
      t('OUTSIDER_CRM.SETTINGS.GOALS.SAVED', {
        month: formatMonth(month.value),
      })
    );
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

watch(month, load);
onMounted(load);
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.GOALS.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.GOALS.DESCRIPTION')"
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

    <div class="flex flex-wrap items-center gap-2">
      <Button
        icon="i-lucide-chevron-left"
        size="sm"
        variant="faded"
        color="slate"
        :aria-label="t('OUTSIDER_CRM.GOALS.PREVIOUS')"
        @click="month = shiftMonth(month, -1)"
      />
      <span
        class="px-1 text-sm font-medium inline-block first-letter:uppercase text-n-slate-12"
      >
        {{ formatMonth(month) }}
      </span>
      <Button
        icon="i-lucide-chevron-right"
        size="sm"
        variant="faded"
        color="slate"
        :aria-label="t('OUTSIDER_CRM.GOALS.NEXT')"
        @click="month = shiftMonth(month, 1)"
      />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <span class="text-xs text-n-slate-11">
        {{
          !from
            ? t('OUTSIDER_CRM.SETTINGS.GOALS.NONE_YET')
            : from === month
              ? t('OUTSIDER_CRM.SETTINGS.GOALS.SET_HERE')
              : t('OUTSIDER_CRM.SETTINGS.GOALS.INHERITED', {
                  month: formatMonth(from),
                })
        }}
      </span>
    </div>

    <div
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        class="flex items-center justify-between gap-3 px-4 py-2.5 text-xs font-medium border-b border-n-weak text-n-slate-11"
      >
        <span>{{ t('OUTSIDER_CRM.SETTINGS.GOALS.UNITS') }}</span>
        <span v-if="unitTotal">
          {{
            t('OUTSIDER_CRM.SETTINGS.GOALS.TOTAL', {
              value: formatMoney(unitTotal),
            })
          }}
        </span>
      </div>
      <label
        v-for="unit in activeUnits"
        :key="unit.id"
        class="flex items-center justify-between gap-3 px-4 py-2 border-b border-n-weak last:border-0"
      >
        <span class="text-sm truncate text-n-slate-12">{{ unit.name }}</span>
        <Input
          v-model="unitValues[unit.id]"
          inputmode="decimal"
          class="w-44 shrink-0"
          :placeholder="t('OUTSIDER_CRM.SETTINGS.GOALS.PLACEHOLDER')"
        />
      </label>
    </div>

    <div
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        class="px-4 py-2.5 text-xs font-medium border-b border-n-weak text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.GOALS.SELLERS') }}
      </div>
      <p
        v-if="!isLoading && !people.length"
        class="p-4 mb-0 text-sm text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.GOALS.NO_PEOPLE') }}
      </p>
      <label
        v-for="person in people"
        :key="person.id"
        class="flex items-center justify-between gap-3 px-4 py-2 border-b border-n-weak last:border-0"
      >
        <span class="flex items-center min-w-0 gap-2">
          <Avatar
            :name="person.name"
            :src="person.thumbnail"
            :size="24"
            rounded-full
          />
          <span class="flex flex-col min-w-0">
            <span class="text-sm truncate text-n-slate-12">
              {{ person.name }}
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{
                person.units.length
                  ? person.units.join(', ')
                  : t('OUTSIDER_CRM.SETTINGS.GOALS.ADMIN')
              }}
            </span>
          </span>
        </span>
        <Input
          v-model="userValues[person.id]"
          inputmode="decimal"
          class="w-44 shrink-0"
          :placeholder="t('OUTSIDER_CRM.SETTINGS.GOALS.PLACEHOLDER')"
        />
      </label>
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.SETTINGS.GOALS.HELP') }}
    </p>
  </SettingsSection>
</template>
