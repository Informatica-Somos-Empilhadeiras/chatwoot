<script setup>
// OUTSIDER: menu lateral do computador e do tablet (768 px ou mais). Entra no lugar do menu do
// Chatwoot pelo Sidebar.vue, que continua dono dos itens (menuItems), das permissões e dos atalhos
// de teclado; no celular o Sidebar.vue segue com o menu dele e a barra de baixo (MobileTabbar.vue).
//
// Painel flutuante, de cima para baixo:
//  - perfil (foto, "Boa noite", nome e conta; menu do perfil) e o botão de recolher;
//  - telefone em destaque (status, ramal e "Ligar");
//  - busca e nova conversa;
//  - seções com título (Atendimento, Vendas, Gestão e "Mais" para o que vier de novo, ver
//    sections.js); um módulo aberto por vez, com a árvore das opções; Canais num bloco próprio logo
//    depois de Conversas;
//  - Configurações com os atalhos em ícones;
//  - no rodapé, a empresa e o tema do menu.
//
// Aberto (270 px) ou recolhido (68 px, só ícones e um quadro ao lado com as opções), escolha que
// fica salva nas preferências da pessoa (a mesma do Chatwoot, sidebar_width). No tablet em pé ele
// fica recolhido e o botão abre o menu por cima da tela, sem empurrar a conversa.
//
// Tema do menu (botão do rodapé, salvo em outsider_nav_theme): claro, em vidro, ou escuro, com o
// brilho verde. Sem escolha, segue o tema do Chatwoot.
import { computed, nextTick, provide, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMutationObserver, useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';
import { useSidebarContext } from 'dashboard/components-next/sidebar/provider';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import Logo from 'next/icon/Logo.vue';
import NavProfile from './NavProfile.vue';
import NavModule from './NavModule.vue';
import NavChannels from './NavChannels.vue';
import NavSettings from './NavSettings.vue';
import NavPhone from './NavPhone.vue';
import {
  makeAllowed,
  toModules,
  itemsOf,
  countOf as countOfItem,
  moduleCount,
  findActiveItem,
  moduleOfItem,
} from '../navModel';
import { groupBySection } from '../sections';
import { closeFlyout } from './navState';
import './nav.css';

const props = defineProps({
  menuItems: { type: Array, default: () => [] },
});

const emit = defineEmits(['openKeyShortcutModal', 'showCreateAccountModal']);

const EXPANDED_WIDTH = 270;
const COLLAPSED_WIDTH = 68;
// espaço em volta do painel flutuante (dentro da faixa do menu)
const GUTTER = 16;
// mesmos valores do provider.js do Chatwoot, para a preferência valer nos dois menus
const SAVED_EXPANDED = 200;
const SAVED_COLLAPSED = 56;
const COLLAPSED_THRESHOLD = 160;
const TABLET = 1024;
// módulos com lugar próprio no menu (fora das seções)
const CONVERSATION = 'Conversation';
const CHANNELS = 'Channels';
const SETTINGS = 'Settings';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const searchShortcut = useKbd(['$mod', 'k']);
const { uiSettings, updateUISettings } = useUISettings();
const { isAllowed, resolvePath, sidebarWidth } = useSidebarContext();
const { width: windowWidth } = useWindowSize();
const currentAccount = useMapGetter('getCurrentAccount');

// ---------- itens ----------
const allowed = makeAllowed(isAllowed);
const modules = computed(() => toModules(props.menuItems, allowed));
const activeItem = computed(() =>
  findActiveItem(modules.value, route, resolvePath)
);
const activeModuleName = computed(
  () => moduleOfItem(modules.value, activeItem.value)?.name || null
);
const countOf = item => countOfItem(item, store.getters);
const countOfModule = module => moduleCount(module, store.getters);

// Canais saem de Conversas para o bloco próprio; Configurações vão para o fim
const conversation = computed(() =>
  modules.value.find(module => module.name === CONVERSATION)
);
const channels = computed(() =>
  conversation.value?.groups.find(group => group.name === CHANNELS)
);
const settings = computed(() =>
  modules.value.find(module => module.name === SETTINGS)
);
const listedModules = computed(() =>
  modules.value
    .filter(module => module.name !== SETTINGS)
    .map(module =>
      module.name === CONVERSATION
        ? {
            ...module,
            groups: module.groups.filter(group => group.name !== CHANNELS),
          }
        : module
    )
    .filter(module => module.to || module.groups.length)
);
const sections = computed(() => groupBySection(listedModules.value));
const manageChannelsTo = computed(
  () =>
    (settings.value ? itemsOf(settings.value) : []).find(
      item => item.name === 'Settings Inboxes'
    )?.to || null
);

// um módulo aberto por vez; ao trocar de tela, abre o módulo dela
const openModule = ref(null);
watch(
  activeModuleName,
  name => {
    if (name) openModule.value = name;
  },
  { immediate: true }
);
const toggleModule = name => {
  openModule.value = openModule.value === name ? null : name;
};
// o destino ativo fica sempre à vista (ex.: um canal ou uma opção lá embaixo)
const navRef = ref(null);
watch(activeItem, async () => {
  await nextTick();
  navRef.value
    ?.querySelector('.onav-leaf.on, .onav-ch.on, .onav-row.on')
    ?.scrollIntoView({ block: 'nearest' });
});

// ---------- aberto / recolhido ----------
const isTablet = computed(() => windowWidth.value < TABLET);
const savedCollapsed = computed(
  () => (sidebarWidth?.value ?? SAVED_EXPANDED) < COLLAPSED_THRESHOLD
);
const overlayOpen = ref(false);
const collapsed = computed(() =>
  isTablet.value ? !overlayOpen.value : savedCollapsed.value
);

const toggleCollapsed = () => {
  closeFlyout();
  if (isTablet.value) {
    overlayOpen.value = !overlayOpen.value;
    return;
  }
  const next = savedCollapsed.value ? SAVED_EXPANDED : SAVED_COLLAPSED;
  if (sidebarWidth) sidebarWidth.value = next;
  updateUISettings({ sidebar_width: next });
};

const closeOverlay = () => {
  overlayOpen.value = false;
};
watch(() => route.fullPath, closeOverlay);
watch(isTablet, closeOverlay);

const isOverlay = computed(() => isTablet.value && overlayOpen.value);
const panelWidth = computed(() =>
  collapsed.value ? COLLAPSED_WIDTH : EXPANDED_WIDTH
);
const shellWidth = computed(
  () => (isTablet.value ? COLLAPSED_WIDTH : panelWidth.value) + GUTTER
);

// ---------- tema do menu ----------
const appDark = ref(document.body.classList.contains('dark'));
useMutationObserver(
  document.body,
  () => {
    appDark.value = document.body.classList.contains('dark');
  },
  { attributes: true, attributeFilter: ['class'] }
);
const isDark = computed(() => {
  const choice = uiSettings.value?.outsider_nav_theme;
  if (choice === 'night') return true;
  if (choice === 'light') return false;
  return appDark.value;
});
// "dark" faz as peças do Chatwoot dentro do menu (nova conversa, menu do perfil) ficarem escuras
const themeClass = computed(() =>
  isDark.value ? 'onav-theme-dark dark' : 'onav-theme-light'
);
provide('outsiderNavThemeClass', themeClass);
const toggleTheme = () => {
  updateUISettings({ outsider_nav_theme: isDark.value ? 'light' : 'night' });
};
const themeLabel = computed(() =>
  isDark.value ? t('OUTSIDER_NAV.THEME_LIGHT') : t('OUTSIDER_NAV.THEME_DARK')
);

const clickOutsideOptions = {
  ignore: ['[data-nav-flyout]', '[data-popover-content]'],
};
</script>

<template>
  <div
    class="onav-shell relative h-full shrink-0 transition-[width] duration-200 ease-out"
    :class="isDark ? '' : 'onav-theme-light'"
    :style="{ width: `${shellWidth}px` }"
    data-outsider-desktop-nav
  >
    <aside
      v-on-click-outside="[closeOverlay, clickOutsideOptions]"
      class="onav absolute top-2 bottom-2 ltr:left-2 rtl:right-2 z-40 transition-[width] duration-200 ease-out"
      :class="[
        themeClass,
        collapsed ? 'onav--rail' : 'onav--open',
        { 'onav--overlay': isOverlay },
      ]"
      :style="{ width: `${panelWidth}px` }"
      :aria-label="t('OUTSIDER_NAV.LABEL')"
    >
      <!-- ===== perfil e recolher ===== -->
      <NavProfile
        :collapsed="collapsed"
        @toggle-collapsed="toggleCollapsed"
        @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        @show-create-account-modal="emit('showCreateAccountModal')"
      />
      <!-- ===== telefone em destaque, logo abaixo do nome ===== -->
      <NavPhone :collapsed="collapsed" />
      <div class="onav-dv" />

      <!-- ===== buscar e nova conversa ===== -->
      <div class="onav-sr">
        <RouterLink
          v-if="!collapsed"
          :to="{ name: 'search' }"
          class="onav-si"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 shrink-0" />
          <span class="flex-1 min-w-0 truncate">
            {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
          </span>
          <kbd>{{ searchShortcut }}</kbd>
        </RouterLink>
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <button
              type="button"
              class="onav-nw"
              :class="{ 'is-open': isOpen }"
              :title="t('OUTSIDER_NAV.NEW_CONVERSATION')"
              :aria-label="t('OUTSIDER_NAV.NEW_CONVERSATION')"
            >
              <span class="i-lucide-pen-line size-[18px]" />
            </button>
          </template>
        </ComposeConversation>
        <RouterLink
          v-if="collapsed"
          v-tooltip.right="t('COMBOBOX.SEARCH_PLACEHOLDER')"
          :to="{ name: 'search' }"
          class="onav-si"
          :aria-label="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-5" />
        </RouterLink>
      </div>

      <!-- ===== módulos por seção ===== -->
      <nav ref="navRef" class="onav-scroll">
        <section
          v-for="(section, index) in sections"
          :key="section.key"
          class="onav-section"
          :data-nav-section="section.key"
        >
          <div v-if="index > 0 || collapsed" class="onav-dv" />
          <h3 v-if="!collapsed" class="onav-sec">{{ t(section.label) }}</h3>
          <ul class="onav-list">
            <template v-for="module in section.modules" :key="module.name">
              <NavModule
                :module="module"
                :collapsed="collapsed"
                :open="openModule === module.name"
                :active-here="activeModuleName === module.name"
                :active-item="activeItem"
                :count="countOfModule(module)"
                :count-of="countOf"
                @toggle="toggleModule(module.name)"
              />
              <NavChannels
                v-if="module.name === CONVERSATION && channels"
                :group="channels"
                :collapsed="collapsed"
                :active-item="activeItem"
                :count-of="countOf"
                :manage-to="manageChannelsTo"
              />
            </template>
          </ul>
        </section>

        <!-- ===== configurações ===== -->
        <section
          v-if="settings"
          class="onav-section"
          :data-nav-section="SETTINGS"
        >
          <div class="onav-dv" />
          <ul class="onav-list">
            <NavSettings
              :module="settings"
              :collapsed="collapsed"
              :active-here="activeModuleName === SETTINGS"
              :active-item="activeItem"
              :count-of="countOf"
            />
          </ul>
        </section>
      </nav>

      <!-- ===== empresa e tema do menu ===== -->
      <footer class="onav-ft">
        <template v-if="!collapsed">
          <span class="onav-mk"><Logo /></span>
          <span class="flex-1 min-w-0 truncate">{{ currentAccount?.name }}</span>
        </template>
        <button
          v-tooltip.top="themeLabel"
          type="button"
          class="onav-cb"
          :aria-label="themeLabel"
          data-outsider-nav-theme
          @click="toggleTheme"
        >
          <span
            class="size-4"
            :class="isDark ? 'i-lucide-sun-medium' : 'i-lucide-moon'"
          />
        </button>
      </footer>
    </aside>
  </div>
</template>
