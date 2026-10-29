<script setup>
// OUTSIDER: Telefonia > Configurações > Filiais (Entrega 25; ver app/services/outsider/voice/settings_billing.rb):
// o nome de cada filial e a filial de cada pessoa, para o painel separar ligações e custos por filial. O id
// da filial nova sai daqui (o servidor guarda o mesmo), para a pessoa já poder ficar nela antes de salvar.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  people: { type: Array, default: () => [] },
  errors: { type: Array, default: () => [] },
});

const form = defineModel('form', { type: Object, required: true });

const { t } = useI18n();

const newId = () =>
  Array.from({ length: 8 }, () =>
    'abcdefghijklmnopqrstuvwxyz0123456789'.charAt(
      Math.floor(Math.random() * 36)
    )
  ).join('');

const branchOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.SETTINGS.BRANCHES.NONE') },
  ...form.value.branches
    .filter(branch => branch.name.trim())
    .map(branch => ({ value: branch.id, label: branch.name })),
]);

const peopleIn = id =>
  Object.values(form.value.agents).filter(agent => agent.branch === id).length;

const addBranch = () => {
  form.value.branches.push({ id: newId(), name: '' });
};

// quem estava na filial apagada fica sem filial
const removeBranch = index => {
  const [branch] = form.value.branches.splice(index, 1);
  Object.values(form.value.agents).forEach(agent => {
    if (agent.branch === branch.id) agent.branch = '';
  });
};
</script>

<template>
  <div
    class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
  >
    <div class="flex flex-col gap-1 px-4 py-3 border-b border-n-weak">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_VOICE.SETTINGS.BRANCHES.LIST') }}
      </h4>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.SETTINGS.BRANCHES.LIST_HELP') }}
      </p>
    </div>
    <p
      v-if="!form.branches.length"
      class="px-4 py-3 mb-0 text-sm border-b text-n-slate-11 border-n-weak"
    >
      {{ t('OUTSIDER_VOICE.SETTINGS.BRANCHES.EMPTY') }}
    </p>
    <div
      v-for="(branch, index) in form.branches"
      :key="branch.id"
      class="flex items-center gap-2 px-4 py-2 border-b border-n-weak"
      data-testid="voice-branch-row"
    >
      <Input
        v-model="branch.name"
        class="flex-1"
        maxlength="60"
        :placeholder="t('OUTSIDER_VOICE.SETTINGS.BRANCHES.NAME')"
        :message-type="
          errors.includes(`branches.${index}.name`) ? 'error' : 'info'
        "
      />
      <span class="w-24 text-xs text-right text-n-slate-11">
        {{ t('OUTSIDER_VOICE.SETTINGS.BRANCHES.PEOPLE', peopleIn(branch.id)) }}
      </span>
      <Button
        icon="i-lucide-trash-2"
        size="sm"
        variant="ghost"
        color="slate"
        :title="t('OUTSIDER_VOICE.SETTINGS.NUMBERS.REMOVE')"
        @click="removeBranch(index)"
      />
    </div>
    <div class="px-4 py-2">
      <Button
        icon="i-lucide-plus"
        size="sm"
        variant="ghost"
        :label="t('OUTSIDER_VOICE.SETTINGS.BRANCHES.ADD')"
        data-testid="voice-branch-add"
        @click="addBranch"
      />
    </div>
  </div>

  <div
    class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
  >
    <div class="flex flex-col gap-1 px-4 py-3 border-b border-n-weak">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_VOICE.SETTINGS.BRANCHES.PEOPLE_TITLE') }}
      </h4>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.SETTINGS.BRANCHES.PEOPLE_HELP') }}
      </p>
    </div>
    <div
      v-for="person in people"
      :key="person.id"
      class="flex flex-wrap items-center justify-between gap-3 px-4 py-2 border-b border-n-weak last:border-0"
      data-testid="voice-branch-person"
    >
      <span class="flex items-center min-w-0 gap-2">
        <Avatar
          :name="person.name"
          :src="person.thumbnail"
          :size="24"
          rounded-full
        />
        <span class="text-sm truncate text-n-slate-12">{{ person.name }}</span>
        <span
          v-if="form.agents[person.id].extension"
          class="text-xs text-n-slate-11"
        >
          {{
            t('OUTSIDER_VOICE.GOALS_SETTINGS.EXTENSION', {
              extension: form.agents[person.id].extension,
            })
          }}
        </span>
      </span>
      <Select
        v-model="form.agents[person.id].branch"
        :options="branchOptions"
        :disabled="!form.branches.length"
      />
    </div>
  </div>
</template>
