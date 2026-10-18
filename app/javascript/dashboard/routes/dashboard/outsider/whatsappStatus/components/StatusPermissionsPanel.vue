<script setup>
// OUTSIDER: aba Permissões, só para administradores. Sem permissão o agente só vê;
// cada ação é liberada separadamente (ver app/services/outsider/whatsapp_status_permissions.rb).
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { errorMessage } from '../helpers';

const { t } = useI18n();

const users = ref([]);
const isLoading = ref(true);
const search = ref('');

// a mesma lista de Outsider::WhatsappStatusPermissions::ALL
const permissions = computed(() => [
  {
    key: 'publish',
    label: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.PUBLISH'),
    description: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.PUBLISH_DESCRIPTION'),
  },
  {
    key: 'republish',
    label: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.REPUBLISH'),
    description: t(
      'OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.REPUBLISH_DESCRIPTION'
    ),
  },
  {
    key: 'download',
    label: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.DOWNLOAD'),
    description: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.DOWNLOAD_DESCRIPTION'),
  },
  {
    key: 'export',
    label: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.EXPORT'),
    description: t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.EXPORT_DESCRIPTION'),
  },
]);

// sem acento e sem maiúscula, para "andre" achar "André"
const normalize = text =>
  text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

// agentes primeiro, porque são eles que mudam
const visible = computed(() => {
  const query = normalize(search.value.trim());
  return users.value
    .filter(user => normalize(`${user.name} ${user.email}`).includes(query))
    .sort(
      (a, b) =>
        Number(a.administrator) - Number(b.administrator) ||
        a.name.localeCompare(b.name)
    );
});

const agents = computed(() => users.value.filter(user => !user.administrator));

const countLabel = key =>
  t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.COUNT', {
    granted: agents.value.filter(user => user.permissions.includes(key)).length,
    count: agents.value.length,
  });

const setPermission = (userId, key, allowed) => {
  users.value = users.value.map(user => {
    if (user.id !== userId) return user;
    const others = user.permissions.filter(permission => permission !== key);
    return { ...user, permissions: allowed ? [...others, key] : others };
  });
};

// salva na hora; se o servidor recusar, a chave volta
const toggle = async (user, key) => {
  const allowed = !user.permissions.includes(key);
  setPermission(user.id, key, allowed);
  try {
    await WhatsappStatusAPI.updatePermission(user.id, key, allowed);
  } catch (error) {
    setPermission(user.id, key, !allowed);
    useAlert(errorMessage(t, error));
  }
};

onMounted(async () => {
  try {
    const { data } = await WhatsappStatusAPI.getPermissions();
    users.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div class="flex flex-col max-w-2xl gap-1">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.TITLE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.DESCRIPTION') }}
        </p>
      </div>
      <Input
        v-model="search"
        type="search"
        :placeholder="t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.SEARCH')"
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

    <div v-if="isLoading" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        class="hidden md:grid grid-cols-[minmax(0,1fr)_repeat(4,8rem)] items-end gap-2 px-4 py-3 border-b border-n-weak"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.NAME') }}
        </span>
        <span
          v-for="permission in permissions"
          :key="permission.key"
          v-tooltip.top="permission.description"
          class="flex flex-col items-center text-center cursor-help"
        >
          <span class="text-xs font-medium text-n-slate-12">
            {{ permission.label }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ countLabel(permission.key) }}
          </span>
        </span>
      </div>
      <ul class="flex flex-col list-none divide-y divide-n-weak">
        <li
          v-for="user in visible"
          :key="user.id"
          class="flex flex-col gap-3 px-4 py-3 md:grid md:grid-cols-[minmax(0,1fr)_repeat(4,8rem)] md:items-center md:gap-2"
        >
          <div class="flex items-center min-w-0 gap-3">
            <Avatar
              :name="user.name"
              :src="user.avatar_url"
              :size="32"
              rounded-full
            />
            <div class="flex flex-col min-w-0">
              <span class="flex items-center min-w-0 gap-2">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ user.name }}
                </span>
                <Label
                  v-if="user.administrator"
                  :label="t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.ADMIN')"
                  color="blue"
                  compact
                />
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ user.email }}
              </span>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-x-6 gap-y-2 md:contents">
            <label
              v-for="permission in permissions"
              :key="permission.key"
              v-tooltip.top="
                user.administrator
                  ? t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.ADMIN_HINT')
                  : null
              "
              class="flex items-center justify-between gap-2 mb-0 md:justify-center"
            >
              <span class="text-sm text-n-slate-11 md:hidden">
                {{ permission.label }}
              </span>
              <Switch v-if="user.administrator" :model-value="true" disabled />
              <Switch
                v-else
                :model-value="user.permissions.includes(permission.key)"
                @update:model-value="toggle(user, permission.key)"
              />
            </label>
          </div>
        </li>
      </ul>
      <p
        v-if="!visible.length"
        class="p-8 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.EMPTY_SEARCH') }}
      </p>
    </div>

    <p class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_WHATSAPP_STATUS.PERMISSIONS.NOTE') }}
    </p>
  </div>
</template>
