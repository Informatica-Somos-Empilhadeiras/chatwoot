<script setup>
// OUTSIDER: metas mensais de ligação por vendedor (Entrega 22; ver app/services/outsider/crm/call_goals.rb):
// ligações feitas e minutos em ligação. Como as metas de venda, a meta gravada num mês vale para os
// seguintes até mudar; vazio = sem meta. Aparecem só vendedores com ramal ligado em Telefonia.
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SettingsSection from './SettingsSection.vue';
import {
  currentMonth,
  errorMessage,
  formatMonth,
  shiftMonth,
} from '../../helpers';

const { t } = useI18n();

const month = ref(currentMonth());
const from = ref(null);
const people = ref([]);
const values = ref({});
const isLoading = ref(true);
const isSaving = ref(false);

const apply = data => {
  from.value = data.from;
  people.value = data.people;
  values.value = Object.fromEntries(
    data.people.map(person => [
      person.id,
      {
        calls: data.users[person.id]?.calls ?? '',
        minutes: data.users[person.id]?.minutes ?? '',
      },
    ])
  );
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await VoiceAPI.getGoals(month.value);
    apply(data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await VoiceAPI.updateGoals(month.value, values.value);
    apply(data);
    useAlert(
      t('OUTSIDER_VOICE.GOALS_SETTINGS.SAVED', {
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
    :title="t('OUTSIDER_VOICE.GOALS_SETTINGS.TITLE')"
    :description="t('OUTSIDER_VOICE.GOALS_SETTINGS.DESCRIPTION')"
  >
    <template #actions>
      <Button
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="isLoading || !people.length"
        data-testid="call-goals-save"
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
        class="inline-block px-1 text-sm font-medium first-letter:uppercase text-n-slate-12"
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
        class="flex items-center justify-end gap-3 px-4 py-2.5 text-xs font-medium border-b border-n-weak text-n-slate-11"
      >
        <span class="w-32 text-center">
          {{ t('OUTSIDER_VOICE.GOALS_SETTINGS.CALLS') }}
        </span>
        <span class="w-32 text-center">
          {{ t('OUTSIDER_VOICE.GOALS_SETTINGS.MINUTES') }}
        </span>
      </div>
      <p
        v-if="!isLoading && !people.length"
        class="p-4 mb-0 text-sm text-n-slate-11"
      >
        {{ t('OUTSIDER_VOICE.GOALS_SETTINGS.NO_PEOPLE') }}
      </p>
      <div
        v-for="person in people"
        :key="person.id"
        class="flex items-center justify-between gap-3 px-4 py-2 border-b border-n-weak last:border-0"
        data-testid="call-goal-row"
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
                t('OUTSIDER_VOICE.GOALS_SETTINGS.EXTENSION', {
                  extension: person.extension,
                })
              }}
              <template v-if="person.state">· {{ person.state }}</template>
            </span>
          </span>
        </span>
        <span class="flex items-center gap-3">
          <Input
            v-model="values[person.id].calls"
            type="number"
            inputmode="numeric"
            class="w-32"
            :placeholder="t('OUTSIDER_VOICE.GOALS_SETTINGS.PLACEHOLDER')"
          />
          <Input
            v-model="values[person.id].minutes"
            type="number"
            inputmode="numeric"
            class="w-32"
            :placeholder="t('OUTSIDER_VOICE.GOALS_SETTINGS.PLACEHOLDER')"
          />
        </span>
      </div>
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_VOICE.GOALS_SETTINGS.HELP') }}
    </p>
  </SettingsSection>
</template>
