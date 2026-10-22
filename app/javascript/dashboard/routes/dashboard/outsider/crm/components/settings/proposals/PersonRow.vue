<script setup>
// OUTSIDER: uma pessoa em Configurações > Propostas > Pessoas: de quem vê as propostas, se cadastra no
// catálogo e a assinatura. Salva a linha inteira; administrador só tem a assinatura para editar.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { settingsError } from './proposalSettings';

const props = defineProps({
  person: { type: Object, required: true },
  people: { type: Array, required: true },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();

const form = ref({});
const isSaving = ref(false);

const storedAccess = computed(() => ({
  view: props.person.access?.view || 'own',
  user_ids: [...(props.person.access?.user_ids || [])].sort((a, b) => a - b),
  catalog: !!props.person.access?.catalog,
}));
const storedSignature = computed(() => ({
  title: props.person.signature?.title || '',
  phone: props.person.signature?.phone || '',
}));

const reset = () => {
  form.value = {
    ...storedAccess.value,
    user_ids: [...storedAccess.value.user_ids],
    ...storedSignature.value,
  };
};

// a lista toda volta do servidor a cada alteração; só esta linha volta ao gravado se ela mudou
watch(
  () => JSON.stringify([storedAccess.value, storedSignature.value]),
  reset,
  { immediate: true }
);

const viewOptions = computed(() =>
  ['own', 'users', 'all'].map(view => ({
    value: view,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.VIEWS.${view.toUpperCase()}`
    ),
  }))
);

const otherOptions = computed(() =>
  props.people
    .filter(other => other.id !== props.person.id)
    .map(other => ({ value: other.id, label: other.name }))
);

const accessForm = computed(() => ({
  view: form.value.view,
  user_ids:
    form.value.view === 'users'
      ? [...form.value.user_ids].sort((a, b) => a - b)
      : [],
  catalog: !!form.value.catalog,
}));

const accessChanged = computed(
  () =>
    !props.person.administrator &&
    JSON.stringify(accessForm.value) !==
      JSON.stringify({
        ...storedAccess.value,
        user_ids:
          storedAccess.value.view === 'users'
            ? storedAccess.value.user_ids
            : [],
      })
);
const signatureChanged = computed(
  () =>
    form.value.title.trim() !== storedSignature.value.title ||
    form.value.phone.trim() !== storedSignature.value.phone
);
const isDirty = computed(() => accessChanged.value || signatureChanged.value);
const missingUsers = computed(
  () => form.value.view === 'users' && !form.value.user_ids.length
);

const save = async () => {
  // guarda antes: a primeira resposta atualiza a linha e o formulário volta ao gravado
  const access = accessChanged.value ? accessForm.value : null;
  const signature = signatureChanged.value
    ? { title: form.value.title.trim(), phone: form.value.phone.trim() }
    : null;
  isSaving.value = true;
  // cada resposta traz as configurações inteiras; vale a última que deu certo
  let data = null;
  try {
    if (access) {
      ({ data } = await CrmAPI.updateProposalAccess(props.person.id, access));
    }
    if (signature) {
      ({ data } = await CrmAPI.updateProposalSignatureOf(
        props.person.id,
        signature
      ));
    }
    emit('updated', data);
    useAlert(
      t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.SAVED', {
        name: props.person.name,
      })
    );
  } catch (error) {
    if (data) emit('updated', data);
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <li class="flex flex-col gap-3 px-4 py-4">
    <div class="flex items-center gap-3 min-w-0">
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
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.ADMIN')"
            color="blue"
            compact
          />
        </span>
        <span class="text-xs truncate text-n-slate-11">
          {{ person.email }}
        </span>
      </div>
    </div>

    <div
      class="grid items-start gap-3 lg:grid-cols-[minmax(0,1.5fr)_auto_minmax(0,1fr)_minmax(0,1fr)]"
    >
      <!-- Vê as propostas de -->
      <div class="flex flex-col gap-1.5 min-w-0">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.VIEW') }}
        </span>
        <span
          v-if="person.administrator"
          class="flex items-center h-9 text-sm text-n-slate-12"
        >
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.ADMIN_VIEW') }}
        </span>
        <template v-else>
          <Select
            v-model="form.view"
            :options="viewOptions"
            class="!w-full [&>select]:w-full"
          />
          <TagMultiSelectComboBox
            v-if="form.view === 'users'"
            :model-value="form.user_ids"
            :options="otherOptions"
            :placeholder="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.PICK')"
            :search-placeholder="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.SEARCH')
            "
            :empty-state="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.EMPTY_SEARCH')
            "
            :message="
              missingUsers
                ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.PICK_HELP')
                : ''
            "
            @update:model-value="ids => (form.user_ids = [...ids])"
          />
        </template>
      </div>

      <!-- Catálogo -->
      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.CATALOG') }}
        </span>
        <span
          v-tooltip.top="
            person.administrator
              ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.ADMIN_CATALOG')
              : null
          "
          class="flex items-center h-9"
        >
          <Switch v-if="person.administrator" model-value disabled />
          <Switch v-else v-model="form.catalog" />
        </span>
      </div>

      <!-- Assinatura -->
      <div class="flex flex-col gap-1.5 min-w-0">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.TITLE') }}
        </span>
        <Input
          v-model="form.title"
          size="sm"
          maxlength="120"
          :placeholder="
            t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.TITLE_PLACEHOLDER')
          "
        />
      </div>
      <div class="flex flex-col gap-1.5 min-w-0">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.PHONE') }}
        </span>
        <Input
          v-model="form.phone"
          size="sm"
          type="tel"
          maxlength="120"
          :placeholder="
            t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PEOPLE.PHONE_PLACEHOLDER')
          "
        />
      </div>
    </div>

    <div v-if="isDirty" class="flex items-center gap-2">
      <Button
        size="xs"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        @click="save"
      />
      <Button
        size="xs"
        variant="ghost"
        color="slate"
        :label="t('OUTSIDER_CRM.CANCEL')"
        :disabled="isSaving"
        @click="reset"
      />
    </div>
  </li>
</template>
