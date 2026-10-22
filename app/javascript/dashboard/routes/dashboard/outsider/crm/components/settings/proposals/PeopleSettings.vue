<script setup>
// OUTSIDER: o que cada pessoa da conta vê nas propostas, quem cadastra no catálogo e a assinatura
// (cargo e telefone abaixo do nome do vendedor no PDF). Administradores veem tudo e mexem no catálogo.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import PersonRow from './PersonRow.vue';
import { normalize } from '../../../helpers';

const props = defineProps({
  settings: { type: Object, required: true },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const search = ref('');

const people = computed(() => props.settings.people || []);

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
        (a.name || '').localeCompare(b.name || '')
    );
});
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <p class="max-w-xl mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.DESCRIPTION') }}
      </p>
      <Input
        v-model="search"
        type="search"
        :placeholder="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.SEARCH')"
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
    </div>
    <div
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <ul class="flex flex-col list-none divide-y divide-n-weak">
        <PersonRow
          v-for="person in visible"
          :key="person.id"
          :person="person"
          :people="people"
          @updated="data => emit('updated', data)"
        />
      </ul>
      <p
        v-if="!visible.length"
        class="p-8 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.EMPTY_SEARCH') }}
      </p>
    </div>
  </section>
</template>
