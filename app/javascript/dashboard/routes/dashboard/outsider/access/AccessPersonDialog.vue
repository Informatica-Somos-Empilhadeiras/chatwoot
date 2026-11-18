<script setup>
// OUTSIDER: cadastro de gente nova em Perfis de acesso > Pessoas (e a troca do ramal de quem já está na conta).
// Escolhido o tipo, o perfil padrão dele vem marcado e o ramal livre vem sugerido. Técnico não toca nas ligações que
// chegam para a empresa (só nas feitas para o ramal dele); dá para mudar. O convite por e-mail é o do Chatwoot.
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AccessAPI from 'dashboard/api/outsider/access';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { formatPhone } from '../voice/format';

const props = defineProps({
  profiles: { type: Array, default: () => [] },
  voice: { type: Object, default: () => ({ numbers: [], branches: [] }) },
  suggested: { type: String, default: '' },
});
const emit = defineEmits(['saved']);

const TYPES = ['administrator', 'agent', 'technician'];

const { t } = useI18n();
const dialog = ref(null);
const person = ref(null);
const saving = ref(false);
const form = reactive({
  name: '',
  email: '',
  type: 'technician',
  profile_id: '',
  branch: '',
  extension: '',
  number: '',
  inbound: false,
});

const editing = computed(() => !!person.value);
const isAdmin = computed(
  () => (person.value?.type || form.type) === 'administrator'
);
const defaultProfileFor = type =>
  props.profiles.find(profile => profile.default_for === type)?.id ||
  props.profiles.find(profile => profile.kind === type)?.id ||
  '';

const pickType = type => {
  form.type = type;
  form.profile_id = type === 'administrator' ? '' : defaultProfileFor(type);
  form.inbound = type !== 'technician';
};

const lineLabel = line =>
  [formatPhone(line.number), line.label || line.state]
    .filter(Boolean)
    .join(' · ');

const open = value => {
  person.value = value || null;
  if (value) {
    Object.assign(form, {
      name: value.name,
      email: value.email,
      type: value.type,
      profile_id: value.profile_id || '',
      branch: value.voice?.branch || '',
      extension: value.voice?.extension || '',
      number: value.voice?.number || '',
      inbound: value.voice?.inbound !== false,
    });
  } else {
    Object.assign(form, {
      name: '',
      email: '',
      branch: '',
      extension: props.suggested,
      number: '',
    });
    pickType('technician');
  }
  dialog.value?.open();
};

const valid = computed(() => {
  if (form.extension && !/^[1-5]\d\d$/.test(form.extension)) return false;
  if (editing.value) return true;
  return !!form.name.trim() && /\S+@\S+\.\S+/.test(form.email.trim());
});

const errorText = error =>
  t(
    `OUTSIDER_ACCESS.PEOPLE.ERRORS.${(error?.response?.data?.error || 'invalid').toUpperCase()}`,
    t('OUTSIDER_ACCESS.PEOPLE.ERRORS.INVALID')
  );

const save = async () => {
  if (!valid.value || saving.value) return;
  saving.value = true;
  const line = {
    branch: form.branch,
    extension: form.extension.trim(),
    number: form.number,
    inbound: form.inbound,
  };
  try {
    if (editing.value) {
      await AccessAPI.updatePerson(person.value.id, {
        ...line,
        ...(isAdmin.value ? {} : { profile_id: form.profile_id }),
      });
      useAlert(t('OUTSIDER_ACCESS.PEOPLE.UPDATED'));
    } else {
      await AccessAPI.createPerson({
        name: form.name.trim(),
        email: form.email.trim(),
        type: form.type,
        profile_id: form.profile_id || undefined,
        ...line,
      });
      useAlert(t('OUTSIDER_ACCESS.PEOPLE.CREATED'));
    }
    dialog.value?.close();
    emit('saved');
  } catch (error) {
    useAlert(errorText(error));
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    overflow-y-auto
    :title="
      editing
        ? t('OUTSIDER_ACCESS.PEOPLE.EDIT_TITLE', { name: person.name })
        : t('OUTSIDER_ACCESS.PEOPLE.NEW_TITLE')
    "
    :description="editing ? '' : t('OUTSIDER_ACCESS.PEOPLE.NEW_HINT')"
    :confirm-button-label="
      editing
        ? t('OUTSIDER_ACCESS.PEOPLE.SAVE')
        : t('OUTSIDER_ACCESS.PEOPLE.CREATE')
    "
    :disable-confirm-button="!valid"
    :is-loading="saving"
    @confirm="save"
  >
    <div
      class="grid gap-4 sm:grid-cols-2"
      data-testid="outsider-access-person-form"
    >
      <template v-if="!editing">
        <label class="outsider-access-field">
          {{ t('OUTSIDER_ACCESS.PEOPLE.NAME') }}
          <input
            v-model="form.name"
            type="text"
            maxlength="120"
            data-testid="outsider-access-person-name"
          />
        </label>
        <label class="outsider-access-field">
          {{ t('OUTSIDER_ACCESS.PEOPLE.EMAIL') }}
          <input
            v-model="form.email"
            type="email"
            maxlength="200"
            data-testid="outsider-access-person-email"
          />
        </label>
        <div class="sm:col-span-2 outsider-access-field">
          {{ t('OUTSIDER_ACCESS.PEOPLE.TYPE') }}
          <div class="grid grid-cols-3 gap-2 mt-1">
            <button
              v-for="type in TYPES"
              :key="type"
              type="button"
              class="flex flex-col items-start gap-0.5 p-3 text-left border border-solid rounded-xl"
              :class="
                form.type === type
                  ? 'border-n-brand bg-n-brand/5'
                  : 'border-n-weak hover:bg-n-alpha-1'
              "
              :data-testid="`outsider-access-type-${type}`"
              @click="pickType(type)"
            >
              <span class="text-sm font-semibold text-n-slate-12">
                {{ t(`OUTSIDER_ACCESS.TYPES.${type.toUpperCase()}`) }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t(`OUTSIDER_ACCESS.TYPES.${type.toUpperCase()}_HINT`) }}
              </span>
            </button>
          </div>
        </div>
      </template>

      <label v-if="!isAdmin" class="outsider-access-field">
        {{ t('OUTSIDER_ACCESS.PEOPLE.PROFILE') }}
        <select
          v-model="form.profile_id"
          data-testid="outsider-access-person-profile"
        >
          <option
            v-for="profile in profiles"
            :key="profile.id"
            :value="profile.id"
          >
            {{ profile.name }}
            <template v-if="profile.default_for === form.type && !editing">
              {{ t('OUTSIDER_ACCESS.PEOPLE.DEFAULT_MARK') }}
            </template>
          </option>
        </select>
      </label>
      <label class="outsider-access-field">
        {{ t('OUTSIDER_ACCESS.PEOPLE.BRANCH') }}
        <select v-model="form.branch">
          <option value="">{{ t('OUTSIDER_ACCESS.PEOPLE.NO_BRANCH') }}</option>
          <option
            v-for="branch in voice.branches"
            :key="branch.id"
            :value="branch.id"
          >
            {{ branch.name }}
          </option>
        </select>
      </label>
      <label class="outsider-access-field">
        {{ t('OUTSIDER_ACCESS.PEOPLE.EXTENSION_LABEL') }}
        <input
          v-model="form.extension"
          type="text"
          inputmode="numeric"
          maxlength="3"
          :placeholder="t('OUTSIDER_ACCESS.PEOPLE.EXTENSION_PLACEHOLDER')"
          data-testid="outsider-access-person-extension"
        />
        <span
          v-if="!editing && suggested && form.extension === suggested"
          class="text-xs font-normal text-n-teal-11"
        >
          {{ t('OUTSIDER_ACCESS.PEOPLE.EXTENSION_SUGGESTED') }}
        </span>
        <span v-else class="text-xs font-normal text-n-slate-11">
          {{ t('OUTSIDER_ACCESS.PEOPLE.EXTENSION_HINT') }}
        </span>
      </label>
      <label class="outsider-access-field">
        {{ t('OUTSIDER_ACCESS.PEOPLE.NUMBER') }}
        <select v-model="form.number" :disabled="!voice.numbers.length">
          <option value="">
            {{ t('OUTSIDER_ACCESS.PEOPLE.NUMBER_AUTO') }}
          </option>
          <option
            v-for="line in voice.numbers"
            :key="line.number"
            :value="line.number"
          >
            {{ lineLabel(line) }}
          </option>
        </select>
      </label>
      <label
        class="flex items-start gap-2 text-sm sm:col-span-2 text-n-slate-12"
      >
        <input v-model="form.inbound" type="checkbox" class="mt-0.5" />
        <span>
          {{ t('OUTSIDER_ACCESS.PEOPLE.INBOUND') }}
          <span class="block text-xs text-n-slate-11">
            {{ t('OUTSIDER_ACCESS.PEOPLE.INBOUND_HINT') }}
          </span>
        </span>
      </label>
      <p
        v-if="!editing && form.type === 'technician'"
        class="px-3 py-2 text-xs leading-5 rounded-lg sm:col-span-2 bg-n-alpha-2 text-n-slate-11"
      >
        {{ t('OUTSIDER_ACCESS.PEOPLE.TECHNICIAN_NOTE') }}
      </p>
    </div>
  </Dialog>
</template>

<style scoped>
.outsider-access-field {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.8rem;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.outsider-access-field input,
.outsider-access-field select {
  margin: 0 !important;
  font-weight: 400;
}
</style>
