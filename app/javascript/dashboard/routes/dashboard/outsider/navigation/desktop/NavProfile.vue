<script setup>
// OUTSIDER: o perfil no topo do menu lateral: foto com o status, "Boa noite 👋", o nome e a conta.
// Clicando, abre o menu da pessoa: status (online, ocupado, offline), trocar de conta (quem tem mais de
// uma) e as mesmas opções do menu de perfil do Chatwoot (SidebarProfileMenu.vue), que aqui abre para
// baixo. O botão ao lado recolhe e abre o menu lateral.
import { computed } from 'vue';
import Auth from 'dashboard/api/auth';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Icon from 'next/icon/Icon.vue';
import SidebarProfileMenuStatus from 'dashboard/components-next/sidebar/SidebarProfileMenuStatus.vue';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownSeparator,
  DropdownItem,
} from 'next/dropdown-menu/base';

defineProps({
  collapsed: { type: Boolean, default: false },
});

const emit = defineEmits([
  'toggleCollapsed',
  'openKeyShortcutModal',
  'showCreateAccountModal',
]);

const { t } = useI18n();

const currentUser = useMapGetter('getCurrentUser');
const availability = useMapGetter('getCurrentUserAvailability');
const accountId = useMapGetter('getCurrentAccountId');
const currentAccount = useMapGetter('getCurrentAccount');
const globalConfig = useMapGetter('globalConfig/get');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const name = computed(() => currentUser.value?.available_name || '');
const initials = computed(() =>
  name.value
    .split(/\s+/)
    .filter(Boolean)
    .filter((_, index, words) => index === 0 || index === words.length - 1)
    .map(word => word[0])
    .join('')
    .toUpperCase()
);
const accountName = computed(() => currentAccount.value?.name || '');

const greeting = computed(() => {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return t('OUTSIDER_NAV.GREETING.MORNING');
  if (hour >= 12 && hour < 18) return t('OUTSIDER_NAV.GREETING.AFTERNOON');
  return t('OUTSIDER_NAV.GREETING.EVENING');
});

// ---------- trocar de conta (igual ao SidebarAccountSwitcher.vue) ----------
const accounts = computed(() =>
  [...(currentUser.value?.accounts || [])].sort((a, b) =>
    a.name.localeCompare(b.name)
  )
);
const canSwitch = computed(() => accounts.value.length > 1);
const changeAccount = id => {
  window.location.href = `/app/accounts/${id}/dashboard`;
};

// ---------- opções do perfil (as mesmas do SidebarProfileMenu.vue) ----------
const showChatSupport = computed(
  () =>
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONTACT_CHATWOOT_SUPPORT_TEAM
    ) && globalConfig.value.chatwootInboxToken
);

const menuItems = computed(() =>
  [
    {
      show: showChatSupport.value,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.CONTACT_SUPPORT'),
      icon: 'i-lucide-life-buoy',
      click: () => window.$chatwoot?.toggle(),
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.KEYBOARD_SHORTCUTS'),
      icon: 'i-lucide-keyboard',
      click: () => emit('openKeyShortcutModal'),
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.PROFILE_SETTINGS'),
      icon: 'i-lucide-user-pen',
      link: { name: 'profile_settings_index' },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.APPEARANCE'),
      icon: 'i-lucide-palette',
      click: () =>
        document
          .querySelector('ninja-keys')
          ?.open({ parent: 'appearance_settings' }),
    },
    {
      show: true,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.DOCS'),
      icon: 'i-lucide-book',
      link: 'https://www.chatwoot.com/hc/user-guide/en',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.CHANGELOG'),
      icon: 'i-lucide-scroll-text',
      link: 'https://www.chatwoot.com/changelog/',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: currentUser.value?.type === 'SuperAdmin',
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.SUPER_ADMIN_CONSOLE'),
      icon: 'i-lucide-castle',
      link: '/super_admin',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.LOGOUT'),
      icon: 'i-lucide-power',
      click: Auth.logout,
    },
  ].filter(item => item.show)
);
</script>

<template>
  <header class="onav-hd">
    <DropdownContainer class="min-w-0" :class="{ 'flex-1': !collapsed }">
      <template #trigger="{ toggle, isOpen }">
        <button
          type="button"
          class="onav-prof"
          :class="{ 'is-open': isOpen }"
          :title="collapsed ? `${name} · ${accountName}` : undefined"
          :aria-label="t('OUTSIDER_NAV.PROFILE_MENU')"
          :aria-expanded="isOpen"
          data-outsider-nav-profile
          @click="toggle"
        >
          <span class="onav-av">
            <img
              v-if="currentUser?.avatar_url"
              :src="currentUser.avatar_url"
              :alt="name"
            />
            <span v-else>{{ initials }}</span>
            <span class="onav-status" :class="`is-${availability}`" />
          </span>
          <span v-if="!collapsed" class="onav-prof-txt">
            <span class="onav-hi">{{ greeting }} 👋</span>
            <span class="onav-nm">{{ name }}</span>
            <span class="onav-sw">
              <span
                v-if="canSwitch"
                class="i-lucide-arrow-right-left size-3 shrink-0"
              />
              <span>{{ accountName }}</span>
            </span>
          </span>
        </button>
      </template>

      <DropdownBody class="onav-prof-menu z-50">
        <SidebarProfileMenuStatus />
        <template v-if="canSwitch">
          <DropdownSeparator />
          <DropdownSection :title="t('SIDEBAR_ITEMS.SWITCH_ACCOUNT')">
            <DropdownItem
              v-for="account in accounts"
              :key="account.id"
              class="cursor-pointer"
              @click="changeAccount(account.id)"
            >
              <template #label>
                <span class="flex-1 min-w-0 truncate text-n-slate-12">
                  {{ account.name }}
                </span>
                <Icon
                  v-if="account.id === accountId"
                  icon="i-lucide-check"
                  class="text-n-teal-11 size-4 shrink-0"
                />
              </template>
            </DropdownItem>
          </DropdownSection>
        </template>
        <DropdownItem
          v-if="globalConfig.createNewAccountFromDashboard"
          :label="t('CREATE_ACCOUNT.NEW_ACCOUNT')"
          icon="i-lucide-plus"
          :click="() => emit('showCreateAccountModal')"
        />
        <DropdownSeparator />
        <template v-for="item in menuItems" :key="item.label">
          <CustomBrandPolicyWrapper
            :show-on-custom-branded-instance="item.showOnCustomBrandedInstance"
          >
            <DropdownItem v-bind="item" />
          </CustomBrandPolicyWrapper>
        </template>
      </DropdownBody>
    </DropdownContainer>

    <button
      type="button"
      class="onav-cb"
      :title="collapsed ? t('OUTSIDER_NAV.EXPAND') : t('OUTSIDER_NAV.COLLAPSE')"
      :aria-label="collapsed ? t('OUTSIDER_NAV.EXPAND') : t('OUTSIDER_NAV.COLLAPSE')"
      data-outsider-nav-toggle
      @click="emit('toggleCollapsed')"
    >
      <span
        class="size-4"
        :class="
          collapsed
            ? 'i-lucide-chevron-right rtl:rotate-180'
            : 'i-lucide-chevron-left rtl:rotate-180'
        "
      />
    </button>
  </header>
</template>
