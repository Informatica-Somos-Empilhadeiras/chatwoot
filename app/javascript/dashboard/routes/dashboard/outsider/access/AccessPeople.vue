<script setup>
// OUTSIDER: Configurações > Perfis de acesso > Pessoas: quem está na conta, com o tipo (Administrador, Agente,
// Técnico), o perfil e o ramal (filial, número de saída e se toca nas ligações da empresa). "Novo usuário" cadastra
// já com tudo, com o perfil padrão do tipo marcado e o ramal livre sugerido (AccessPersonDialog.vue).
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AccessAPI from 'dashboard/api/outsider/access';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatPhone } from '../voice/format';
import AccessPersonDialog from './AccessPersonDialog.vue';

const props = defineProps({
  profiles: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed']);

const TYPES = ['administrator', 'agent', 'technician'];

const { t } = useI18n();
const loading = ref(true);
const people = ref([]);
const suggested = ref('');
const voice = ref({ enabled: false, numbers: [], branches: [] });
const search = ref('');
const type = ref('');
const dialog = ref(null);

const load = async () => {
  try {
    const { data } = await AccessAPI.people();
    people.value = data.people || [];
    suggested.value = data.suggested_extension || '';
    voice.value = data.voice || voice.value;
  } catch {
    useAlert(t('OUTSIDER_ACCESS.ERRORS.LOAD'));
  } finally {
    loading.value = false;
  }
};
onMounted(load);

const normalize = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

const filtered = computed(() => {
  const query = normalize(search.value.trim());
  return people.value.filter(person => {
    if (type.value && person.type !== type.value) return false;
    if (!query) return true;
    return [person.name, person.email, person.voice?.extension].some(value =>
      normalize(value).includes(query)
    );
  });
});

const countOf = key =>
  people.value.filter(person => person.type === key).length;

const branchName = id =>
  voice.value.branches.find(branch => branch.id === id)?.name || '';

const lineOf = person => {
  const line = person.voice || {};
  if (!line.extension) return t('OUTSIDER_ACCESS.PEOPLE.NO_EXTENSION');
  return [
    t('OUTSIDER_ACCESS.PEOPLE.EXTENSION', { extension: line.extension }),
    branchName(line.branch),
    line.number && formatPhone(line.number),
  ]
    .filter(Boolean)
    .join(' · ');
};

const assignable = computed(() =>
  props.profiles.filter(profile => profile.kind !== 'administrator')
);

const changeProfile = async (person, profileId) => {
  try {
    await AccessAPI.updatePerson(person.id, { profile_id: profileId });
    await load();
    emit('changed');
  } catch {
    useAlert(t('OUTSIDER_ACCESS.ERRORS.SAVE'));
  }
};

const openNew = () => dialog.value?.open(null);

const openEdit = person => dialog.value?.open(person);

const saved = async () => {
  await load();
  emit('changed');
};
</script>

<template>
  <div class="flex flex-col gap-4 pb-10" data-testid="outsider-access-people">
    <div class="flex flex-wrap items-center gap-2">
      <label
        class="flex items-center flex-1 min-w-[14rem] gap-2 px-3 rounded-lg h-9 bg-n-alpha-2 text-n-slate-11"
      >
        <span class="i-lucide-search size-4 shrink-0" />
        <input
          v-model="search"
          type="search"
          class="flex-1 min-w-0 !m-0 !p-0 !border-0 !bg-transparent !h-auto text-sm text-n-slate-12 !outline-none"
          :placeholder="t('OUTSIDER_ACCESS.PEOPLE.SEARCH')"
        />
      </label>
      <button
        type="button"
        class="px-3 py-1.5 text-sm rounded-lg"
        :class="
          !type
            ? 'bg-n-slate-12 text-n-solid-1'
            : 'bg-n-alpha-2 text-n-slate-12'
        "
        @click="type = ''"
      >
        {{ t('OUTSIDER_ACCESS.PEOPLE.ALL', { count: people.length }) }}
      </button>
      <button
        v-for="key in TYPES"
        :key="key"
        type="button"
        class="px-3 py-1.5 text-sm rounded-lg"
        :class="
          type === key
            ? 'bg-n-slate-12 text-n-solid-1'
            : 'bg-n-alpha-2 text-n-slate-12'
        "
        @click="type = key"
      >
        {{ t(`OUTSIDER_ACCESS.TYPES.${key.toUpperCase()}_PLURAL`) }}
        ({{ countOf(key) }})
      </button>
      <Button
        :label="t('OUTSIDER_ACCESS.PEOPLE.NEW')"
        icon="i-lucide-user-plus"
        size="sm"
        data-testid="outsider-access-new-person"
        @click="openNew"
      />
    </div>

    <p v-if="loading" class="text-sm text-n-slate-11">
      {{ t('OUTSIDER_ACCESS.LOADING') }}
    </p>
    <p
      v-else-if="!voice.enabled"
      class="px-3 py-2 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      {{ t('OUTSIDER_ACCESS.PEOPLE.VOICE_OFF') }}
    </p>

    <div
      class="overflow-hidden border divide-y rounded-xl border-n-weak divide-n-weak bg-n-solid-1"
    >
      <div
        v-for="person in filtered"
        :key="person.id"
        class="flex flex-wrap items-center gap-3 px-4 py-3"
        :data-testid="`outsider-access-person-${person.id}`"
      >
        <Avatar
          :name="person.name"
          :src="person.thumbnail || ''"
          :size="36"
          rounded-full
        />
        <div class="flex-1 min-w-[12rem]">
          <p
            class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
          >
            {{ person.name }}
            <span
              class="px-1.5 py-0.5 text-[0.65rem] font-semibold rounded-md"
              :class="{
                'bg-n-violet-3 text-n-violet-11':
                  person.type === 'administrator',
                'bg-n-blue-3 text-n-blue-11': person.type === 'agent',
                'bg-n-teal-3 text-n-teal-11': person.type === 'technician',
              }"
            >
              {{ t(`OUTSIDER_ACCESS.TYPES.${person.type.toUpperCase()}`) }}
            </span>
            <span
              v-if="!person.confirmed"
              class="px-1.5 py-0.5 text-[0.65rem] rounded-md bg-n-alpha-2 text-n-slate-11"
            >
              {{ t('OUTSIDER_ACCESS.PEOPLE.INVITED') }}
            </span>
          </p>
          <p class="text-xs text-n-slate-11">{{ person.email }}</p>
          <p class="flex items-center gap-1 mt-0.5 text-xs text-n-slate-11">
            <span class="i-lucide-phone size-3" />
            {{ lineOf(person) }}
            <template v-if="person.voice?.extension">
              ·
              <span
                :class="
                  person.push_devices ? 'text-n-teal-11' : 'text-n-slate-10'
                "
              >
                {{
                  person.push_devices
                    ? t('OUTSIDER_ACCESS.PEOPLE.PUSH_ON', {
                        count: person.push_devices,
                      })
                    : t('OUTSIDER_ACCESS.PEOPLE.PUSH_OFF')
                }}
              </span>
            </template>
          </p>
        </div>
        <select
          v-if="person.type !== 'administrator'"
          class="!mb-0 !h-8 !py-0 !w-48 text-sm"
          :value="person.profile_id"
          :aria-label="t('OUTSIDER_ACCESS.PEOPLE.PROFILE')"
          @change="changeProfile(person, Number($event.target.value))"
        >
          <option
            v-for="profile in assignable"
            :key="profile.id"
            :value="profile.id"
          >
            {{ profile.name }}
          </option>
        </select>
        <span v-else class="w-48 text-sm text-n-slate-11">
          {{ t('OUTSIDER_ACCESS.PEOPLE.ADMIN_PROFILE') }}
        </span>
        <Button
          :label="t('OUTSIDER_ACCESS.PEOPLE.EDIT_LINE')"
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-phone"
          @click="openEdit(person)"
        />
      </div>
      <p
        v-if="!loading && !filtered.length"
        class="px-4 py-6 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_ACCESS.PEOPLE.EMPTY') }}
      </p>
    </div>

    <AccessPersonDialog
      ref="dialog"
      :profiles="assignable"
      :voice="voice"
      :suggested="suggested"
      @saved="saved"
    />
  </div>
</template>
