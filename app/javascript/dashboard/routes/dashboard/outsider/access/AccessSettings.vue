<script setup>
// OUTSIDER: Configurações > Perfis de acesso (só administradores), no jeito dos ERPs. Aba Perfis: Administrador, Agente
// e Técnico vêm prontos; dá para duplicar e criar outros. Cada tela tem Não vê, Vê, Usa ou Gerencia (só os níveis que
// fazem sentido nela). Um perfil por tipo é o padrão de quem é cadastrado. Telas que o superadministrador deixou só
// para administradores aparecem com cadeado. Aba Pessoas: quem está na conta, com tipo, perfil e ramal, e o cadastro
// novo já com tudo (AccessPeople.vue).
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AccessAPI from 'dashboard/api/outsider/access';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AccessPeople from './AccessPeople.vue';
import { GROUPS, LEVELS } from './catalog';

const { t } = useI18n();

const tab = ref('profiles');
const loading = ref(true);
const saving = ref(false);
const catalog = ref([]);
const locked = ref([]);
const profiles = ref([]);
const selectedId = ref(null);
const draft = ref(null);
const confirmDelete = ref(false);

const selected = computed(
  () => profiles.value.find(profile => profile.id === selectedId.value) || null
);
const isAdminProfile = computed(() => selected.value?.kind === 'administrator');
const isSystem = computed(() => selected.value?.kind !== 'custom');

const groups = computed(() =>
  GROUPS.map(group => ({
    key: group,
    screens: catalog.value.filter(screen => screen.group === group),
  })).filter(group => group.screens.length)
);

const copyDraft = profile => {
  draft.value = profile
    ? {
        name: profile.name,
        description: profile.description || '',
        default_for: profile.default_for || '',
        permissions: { ...profile.permissions },
      }
    : null;
  confirmDelete.value = false;
};

watch(selected, profile => copyDraft(profile));

const dirty = computed(() => {
  const profile = selected.value;
  if (!profile || !draft.value || isAdminProfile.value) return false;
  return (
    draft.value.name !== profile.name ||
    draft.value.description !== (profile.description || '') ||
    draft.value.default_for !== (profile.default_for || '') ||
    Object.keys(draft.value.permissions).some(
      key => draft.value.permissions[key] !== profile.permissions[key]
    )
  );
});

const load = async ({ keep = true } = {}) => {
  try {
    const { data } = await AccessAPI.profiles();
    catalog.value = data.catalog || [];
    locked.value = data.locked || [];
    profiles.value = data.profiles || [];
    if (
      !keep ||
      !profiles.value.some(profile => profile.id === selectedId.value)
    ) {
      selectedId.value =
        profiles.value.find(profile => profile.kind === 'technician')?.id ||
        profiles.value[0]?.id ||
        null;
    }
    copyDraft(selected.value);
  } catch {
    useAlert(t('OUTSIDER_ACCESS.ERRORS.LOAD'));
  } finally {
    loading.value = false;
  }
};

onMounted(() => load({ keep: false }));

const isLocked = screen =>
  !isAdminProfile.value &&
  (screen.admin_only || locked.value.includes(screen.key));

const levelOf = screen => {
  if (isAdminProfile.value) return screen.levels[screen.levels.length - 1];
  if (isLocked(screen)) return 'none';
  return draft.value?.permissions[screen.key] || 'none';
};

const setLevel = (screen, level) => {
  if (isAdminProfile.value || isLocked(screen)) return;
  if (!screen.levels.includes(level)) return;
  draft.value.permissions[screen.key] = level;
};

const membersLabel = count =>
  count === 1
    ? t('OUTSIDER_ACCESS.PROFILES.ONE_MEMBER')
    : t('OUTSIDER_ACCESS.PROFILES.MEMBERS', { count });

const summaryOf = profile => {
  if (profile.kind === 'administrator')
    return t('OUTSIDER_ACCESS.PROFILES.SUMMARY_ALL');
  if (profile.technician) return t('OUTSIDER_ACCESS.PROFILES.SUMMARY_PHONE');
  const open = Object.values(profile.permissions).filter(
    level => level !== 'none'
  ).length;
  return t('OUTSIDER_ACCESS.PROFILES.SUMMARY_SCREENS', { count: open });
};

const tagOf = profile => {
  if (profile.kind === 'administrator')
    return t('OUTSIDER_ACCESS.PROFILES.TAG_SYSTEM');
  if (profile.default_for)
    return t(
      `OUTSIDER_ACCESS.PROFILES.TAG_DEFAULT.${profile.default_for.toUpperCase()}`
    );
  return '';
};

const errorOf = error =>
  t(
    `OUTSIDER_ACCESS.ERRORS.${(error?.response?.data?.error || 'save').toUpperCase()}`,
    t('OUTSIDER_ACCESS.ERRORS.SAVE')
  );

const save = async () => {
  if (!dirty.value) return;
  saving.value = true;
  try {
    await AccessAPI.updateProfile(selected.value.id, {
      name: draft.value.name.trim(),
      description: draft.value.description.trim(),
      default_for: draft.value.default_for,
      permissions: draft.value.permissions,
    });
    await load();
    useAlert(t('OUTSIDER_ACCESS.PROFILES.SAVED'));
  } catch (error) {
    useAlert(errorOf(error));
  } finally {
    saving.value = false;
  }
};

const freeName = base => {
  const names = new Set(profiles.value.map(profile => profile.name));
  if (!names.has(base)) return base;
  let index = 2;
  while (names.has(`${base} ${index}`)) index += 1;
  return `${base} ${index}`;
};

const create = async ({ copy = false } = {}) => {
  saving.value = true;
  try {
    const source = selected.value;
    const name = copy
      ? freeName(t('OUTSIDER_ACCESS.PROFILES.COPY_OF', { name: source.name }))
      : freeName(t('OUTSIDER_ACCESS.PROFILES.NEW_NAME'));
    const { data } = await AccessAPI.createProfile({
      name,
      description: copy ? source.description || '' : '',
      // novo começa como o Agente; duplicar copia as telas do escolhido
      copy_from: copy ? source?.id : null,
    });
    selectedId.value = data.id;
    await load();
  } catch (error) {
    useAlert(errorOf(error));
  } finally {
    saving.value = false;
  }
};

const remove = async () => {
  if (!confirmDelete.value) {
    confirmDelete.value = true;
    return;
  }
  saving.value = true;
  try {
    await AccessAPI.deleteProfile(selected.value.id);
    selectedId.value = null;
    await load({ keep: false });
    useAlert(t('OUTSIDER_ACCESS.PROFILES.DELETED'));
  } catch (error) {
    useAlert(errorOf(error));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SettingsLayout :is-loading="loading">
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_ACCESS.TITLE')"
        :description="t('OUTSIDER_ACCESS.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="flex gap-2 mb-4" role="tablist">
        <button
          v-for="key in ['profiles', 'people']"
          :key="key"
          type="button"
          role="tab"
          class="px-3 py-1.5 text-sm font-medium rounded-lg"
          :class="
            tab === key
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3'
          "
          :aria-selected="tab === key"
          :data-testid="`outsider-access-tab-${key}`"
          @click="tab = key"
        >
          {{ t(`OUTSIDER_ACCESS.TABS.${key.toUpperCase()}`) }}
        </button>
      </div>

      <AccessPeople
        v-if="tab === 'people'"
        :profiles="profiles"
        @changed="load"
      />

      <div v-else class="grid gap-5 pb-10 lg:grid-cols-[17rem_minmax(0,1fr)]">
        <aside class="flex flex-col gap-1.5">
          <button
            v-for="profile in profiles"
            :key="profile.id"
            type="button"
            class="flex flex-col items-start gap-0.5 p-3 text-left border border-solid rounded-xl"
            :class="
              profile.id === selectedId
                ? 'border-n-brand bg-n-brand/5'
                : 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-1'
            "
            :data-testid="`outsider-access-profile-${profile.kind}`"
            @click="selectedId = profile.id"
          >
            <span
              class="flex flex-wrap items-center gap-1.5 text-sm font-semibold text-n-slate-12"
            >
              {{ profile.name }}
              <span
                v-if="tagOf(profile)"
                class="px-1.5 py-0.5 text-[0.65rem] font-semibold rounded-md bg-n-alpha-2 text-n-slate-11"
              >
                {{ tagOf(profile) }}
              </span>
            </span>
            <span class="text-xs text-n-slate-11">
              {{ summaryOf(profile) }} ·
              {{ membersLabel(profile.members_count) }}
            </span>
          </button>
          <button
            type="button"
            class="p-3 text-sm font-semibold text-left border border-dashed rounded-xl border-n-weak text-n-blue-11 hover:bg-n-alpha-1"
            :disabled="saving"
            data-testid="outsider-access-new-profile"
            @click="create()"
          >
            {{ t('OUTSIDER_ACCESS.PROFILES.NEW') }}
          </button>
          <p class="px-1 pt-2 text-xs leading-5 text-n-slate-11">
            {{ t('OUTSIDER_ACCESS.PROFILES.CEILING_HINT') }}
          </p>
        </aside>

        <section
          v-if="selected && draft"
          class="min-w-0 border rounded-xl border-n-weak bg-n-solid-1"
          data-testid="outsider-access-editor"
        >
          <div
            class="flex flex-wrap items-start gap-3 p-4 border-b border-n-weak"
          >
            <div class="flex-1 min-w-[14rem]">
              <input
                v-model="draft.name"
                type="text"
                maxlength="60"
                class="!mb-1 !h-auto !py-1 !px-2 -mx-2 text-base font-semibold !border-transparent hover:!border-n-weak focus:!border-n-brand !bg-transparent text-n-slate-12"
                :disabled="isAdminProfile"
                :aria-label="t('OUTSIDER_ACCESS.PROFILES.NAME')"
              />
              <input
                v-model="draft.description"
                type="text"
                maxlength="200"
                class="!mb-0 !h-auto !py-1 !px-2 -mx-2 text-sm !border-transparent hover:!border-n-weak focus:!border-n-brand !bg-transparent text-n-slate-11"
                :disabled="isAdminProfile"
                :placeholder="t('OUTSIDER_ACCESS.PROFILES.DESCRIPTION')"
              />
            </div>
            <label
              v-if="!isAdminProfile"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              {{ t('OUTSIDER_ACCESS.PROFILES.DEFAULT_FOR') }}
              <select
                v-model="draft.default_for"
                class="!mb-0 !h-8 !py-0 !w-auto text-sm"
                data-testid="outsider-access-default-for"
              >
                <option value="">
                  {{ t('OUTSIDER_ACCESS.PROFILES.DEFAULT_NONE') }}
                </option>
                <option value="agent">
                  {{ t('OUTSIDER_ACCESS.TYPES.AGENT') }}
                </option>
                <option value="technician">
                  {{ t('OUTSIDER_ACCESS.TYPES.TECHNICIAN') }}
                </option>
              </select>
            </label>
            <div class="flex gap-2">
              <Button
                :label="t('OUTSIDER_ACCESS.PROFILES.DUPLICATE')"
                variant="faded"
                color="slate"
                size="sm"
                :disabled="saving"
                @click="create({ copy: true })"
              />
              <Button
                v-if="!isSystem"
                :label="
                  confirmDelete
                    ? t('OUTSIDER_ACCESS.PROFILES.CONFIRM_DELETE')
                    : t('OUTSIDER_ACCESS.PROFILES.DELETE')
                "
                variant="faded"
                color="ruby"
                size="sm"
                :disabled="saving"
                @click="remove"
              />
              <Button
                v-if="!isAdminProfile"
                :label="t('OUTSIDER_ACCESS.PROFILES.SAVE')"
                size="sm"
                :is-loading="saving"
                :disabled="!dirty"
                data-testid="outsider-access-save"
                @click="save"
              />
            </div>
          </div>

          <p
            v-if="isAdminProfile"
            class="px-4 py-3 text-sm border-b text-n-slate-11 border-n-weak bg-n-alpha-1"
          >
            {{ t('OUTSIDER_ACCESS.PROFILES.ADMIN_NOTE') }}
          </p>

          <div class="overflow-x-auto">
            <table class="w-full text-sm outsider-access-table">
              <thead>
                <tr>
                  <th class="w-[40%]">
                    {{ t('OUTSIDER_ACCESS.PROFILES.SCREEN') }}
                  </th>
                  <th>{{ t('OUTSIDER_ACCESS.PROFILES.ACCESS') }}</th>
                  <th class="hidden xl:table-cell">
                    {{ t('OUTSIDER_ACCESS.PROFILES.NOTE') }}
                  </th>
                </tr>
              </thead>
              <tbody v-for="group in groups" :key="group.key">
                <tr class="outsider-access-table__group">
                  <td colspan="3">
                    {{ t(`OUTSIDER_ACCESS.GROUPS.${group.key.toUpperCase()}`) }}
                  </td>
                </tr>
                <tr
                  v-for="screen in group.screens"
                  :key="screen.key"
                  :data-testid="`outsider-access-row-${screen.key}`"
                >
                  <td>
                    <span
                      class="font-medium text-n-slate-12"
                      :class="{ 'ps-4': screen.parent }"
                    >
                      {{
                        t(
                          `OUTSIDER_ACCESS.SCREENS.${screen.key.toUpperCase()}.LABEL`
                        )
                      }}
                    </span>
                    <span
                      v-if="isLocked(screen)"
                      class="ms-1.5 inline-flex items-center gap-1 px-1.5 py-0.5 text-[0.65rem] font-semibold rounded-md bg-n-amber-3 text-n-amber-11"
                    >
                      <span class="i-lucide-lock size-3" />
                      {{ t('OUTSIDER_ACCESS.PROFILES.ADMIN_ONLY') }}
                    </span>
                  </td>
                  <td>
                    <span
                      class="outsider-access-seg"
                      role="radiogroup"
                      :aria-label="
                        t(
                          `OUTSIDER_ACCESS.SCREENS.${screen.key.toUpperCase()}.LABEL`
                        )
                      "
                    >
                      <button
                        v-for="level in LEVELS"
                        :key="level"
                        type="button"
                        role="radio"
                        :aria-checked="levelOf(screen) === level"
                        :class="[
                          `is-${level}`,
                          { 'is-on': levelOf(screen) === level },
                        ]"
                        :disabled="
                          !screen.levels.includes(level) ||
                          isAdminProfile ||
                          isLocked(screen)
                        "
                        :data-testid="`outsider-access-${screen.key}-${level}`"
                        @click="setLevel(screen, level)"
                      >
                        {{ t(`OUTSIDER_ACCESS.LEVELS.${level.toUpperCase()}`) }}
                      </button>
                    </span>
                  </td>
                  <td class="hidden text-xs xl:table-cell text-n-slate-11">
                    {{
                      isLocked(screen) && !screen.admin_only
                        ? t('OUTSIDER_ACCESS.PROFILES.LOCKED_BY_SUPERADMIN')
                        : t(
                            `OUTSIDER_ACCESS.SCREENS.${screen.key.toUpperCase()}.HINT`
                          )
                    }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>

<style scoped>
.outsider-access-table th {
  padding: 0.6rem 1rem;
  text-align: start;
  font-size: 0.75rem;
  font-weight: 600;
  color: rgb(var(--slate-11));
  border-bottom: 1px solid rgb(var(--slate-4));
}

.outsider-access-table td {
  padding: 0.55rem 1rem;
  border-bottom: 1px solid rgb(var(--slate-3));
  vertical-align: middle;
}

.outsider-access-table__group td {
  padding-top: 0.9rem;
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: rgb(var(--slate-11));
  background: rgb(var(--slate-2));
}

.outsider-access-seg {
  display: inline-flex;
  padding: 0.15rem;
  border-radius: 0.6rem;
  background: rgb(var(--slate-3));
  white-space: nowrap;
}

.outsider-access-seg button {
  padding: 0.25rem 0.6rem;
  border-radius: 0.45rem;
  font-size: 0.75rem;
  font-weight: 500;
  color: rgb(var(--slate-11));
}

.outsider-access-seg button:disabled {
  opacity: 0.35;
  cursor: default;
}

.outsider-access-seg button.is-on {
  opacity: 1;
  font-weight: 700;
  color: #fff;
  background: var(--outsider-brand, #00663b);
}

.outsider-access-seg button.is-none.is-on {
  background: rgb(var(--slate-9));
}

.outsider-access-seg button.is-view.is-on {
  background: #2563eb;
}

.outsider-access-seg button.is-manage.is-on {
  background: #7c3aed;
}
</style>
