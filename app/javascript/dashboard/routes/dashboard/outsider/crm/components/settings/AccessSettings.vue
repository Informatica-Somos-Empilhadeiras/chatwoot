<script setup>
// OUTSIDER: Configurações > Acesso, só para administradores. Com o CRM ligado na conta (Super
// Admin), todo agente tem o CRM; aqui o administrador desliga para quem não deve usar. Quem fica
// desligado não vê o menu, a aba e o valor na conversa nem o bloco do contato
// (ver app/services/outsider/crm/switch.rb). Administradores sempre têm o CRM.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';

const { t } = useI18n();

const people = ref([]);
const isLoading = ref(true);
const search = ref('');

// sem acento e sem maiúscula, para "andre" achar "André"
const normalize = text =>
  text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

// agentes primeiro, porque são eles que mudam
const visible = computed(() => {
  const query = normalize(search.value.trim());
  return people.value
    .filter(person =>
      normalize(`${person.name} ${person.email}`).includes(query)
    )
    .sort(
      (a, b) =>
        Number(a.administrator) - Number(b.administrator) ||
        a.name.localeCompare(b.name)
    );
});

const agents = computed(() =>
  people.value.filter(person => !person.administrator)
);

const countLabel = computed(() =>
  t('OUTSIDER_CRM.SETTINGS.ACCESS.COUNT', {
    enabled: agents.value.filter(person => person.enabled).length,
    count: agents.value.length,
  })
);

// administrador vê todas as unidades; agente sem unidade não vê negócio mesmo com o CRM ligado
const unitsLabel = person => {
  if (person.administrator) return t('OUTSIDER_CRM.SETTINGS.ACCESS.ALL_UNITS');
  return person.units.length
    ? person.units.join(', ')
    : t('OUTSIDER_CRM.SETTINGS.ACCESS.NO_UNIT');
};

const setEnabled = (userId, enabled) => {
  people.value = people.value.map(person =>
    person.id === userId ? { ...person, enabled } : person
  );
};

// salva na hora; se o servidor recusar, a chave volta
const toggle = async person => {
  const enabled = !person.enabled;
  setEnabled(person.id, enabled);
  try {
    await CrmAPI.updateAgentAccess(person.id, enabled);
  } catch (error) {
    setEnabled(person.id, !enabled);
    useAlert(errorMessage(t, error));
  }
};

onMounted(async () => {
  try {
    const { data } = await CrmAPI.getAgentAccesses();
    people.value = data.payload;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.ACCESS.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.ACCESS.DESCRIPTION')"
  >
    <template #actions>
      <Input
        v-model="search"
        type="search"
        :placeholder="t('OUTSIDER_CRM.SETTINGS.ACCESS.SEARCH')"
        :custom-input-class="['h-8 ltr:!pl-8 rtl:!pr-8 !py-1']"
        class="w-full sm:w-64"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
          />
        </template>
      </Input>
    </template>

    <div v-if="isLoading" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_CRM.SETTINGS.ACCESS.NAME') }}
        </span>
        <span class="text-xs text-n-slate-11">{{ countLabel }}</span>
      </div>
      <ul class="flex flex-col list-none divide-y divide-n-weak">
        <li
          v-for="person in visible"
          :key="person.id"
          class="flex items-center gap-3 px-4 py-3"
        >
          <Avatar
            :name="person.name"
            :src="person.thumbnail"
            :size="32"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="flex items-center min-w-0 gap-2">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ person.name }}
              </span>
              <Label
                v-if="person.administrator"
                :label="t('OUTSIDER_CRM.SETTINGS.ACCESS.ADMIN')"
                color="blue"
                compact
              />
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{ person.email }}
              ·
              {{ unitsLabel(person) }}
            </span>
            <span
              v-if="!person.enabled && person.open_deals"
              class="flex items-center gap-1 text-xs text-n-amber-11"
            >
              <Icon icon="i-lucide-triangle-alert" class="size-3.5" />
              {{
                t('OUTSIDER_CRM.SETTINGS.ACCESS.OPEN_DEALS', person.open_deals)
              }}
            </span>
          </div>
          <span
            v-tooltip.left="
              person.administrator
                ? t('OUTSIDER_CRM.SETTINGS.ACCESS.ADMIN_HINT')
                : null
            "
            class="flex items-center gap-2 shrink-0"
          >
            <span class="hidden text-xs sm:inline text-n-slate-11">
              {{
                person.enabled
                  ? t('OUTSIDER_CRM.SETTINGS.ACCESS.ON')
                  : t('OUTSIDER_CRM.SETTINGS.ACCESS.OFF')
              }}
            </span>
            <Switch v-if="person.administrator" model-value disabled />
            <Switch
              v-else
              :model-value="person.enabled"
              @update:model-value="toggle(person)"
            />
          </span>
        </li>
      </ul>
      <p
        v-if="!visible.length"
        class="p-8 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.ACCESS.EMPTY_SEARCH') }}
      </p>
    </div>

    <p class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_CRM.SETTINGS.ACCESS.NOTE') }}
    </p>
  </SettingsSection>
</template>
