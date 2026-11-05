<script setup>
// OUTSIDER: menu lateral do computador e do tablet (768 px ou mais). Entra no lugar do menu do
// Chatwoot pelo Sidebar.vue, que continua dono dos itens (menuItems), das permissões e dos atalhos
// de teclado; no celular o Sidebar.vue segue com o menu dele e a barra de baixo (MobileTabbar.vue).
//
// Organização (ver sections.js): seções com título (Atendimento, Vendas, Gestão e "Mais" para o que
// vier de novo), um módulo aberto por vez com as opções logo abaixo, grupos longos (Canais, Pastas,
// Times, Etiquetas) em cartões que abrem e fecham, e um destino ativo só, com a pílula verde.
//
// Aberto (256 px) ou recolhido (72 px, só ícones e um quadro ao lado com as opções), escolha que
// fica salva nas preferências da pessoa (a mesma do Chatwoot, sidebar_width). No tablet em pé ele
// fica recolhido e o botão abre o menu por cima da tela, sem empurrar a conversa.
import { computed, nextTick, provide, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useSidebarContext } from 'dashboard/components-next/sidebar/provider';
import SidebarAccountSwitcher from 'dashboard/components-next/sidebar/SidebarAccountSwitcher.vue';
import SidebarProfileMenu from 'dashboard/components-next/sidebar/SidebarProfileMenu.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Logo from 'next/icon/Logo.vue';
import OutsiderPhoneButton from '../../voice/PhoneButton.vue';
import NavModule from './NavModule.vue';
import {
  makeAllowed,
  toModules,
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

const EXPANDED_WIDTH = 256;
const COLLAPSED_WIDTH = 72;
// mesmos valores do provider.js do Chatwoot, para a preferência valer nos dois menus
const SAVED_EXPANDED = 200;
const SAVED_COLLAPSED = 56;
const COLLAPSED_THRESHOLD = 160;
const TABLET = 1024;

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const searchShortcut = useKbd(['$mod', 'k']);
const { uiSettings, updateUISettings } = useUISettings();
const { isAllowed, resolvePath, sidebarWidth } = useSidebarContext();
const { width: windowWidth } = useWindowSize();

// ---------- itens ----------
const allowed = makeAllowed(isAllowed);
const modules = computed(() => toModules(props.menuItems, allowed));
const sections = computed(() => groupBySection(modules.value));
const activeItem = computed(() =>
  findActiveItem(modules.value, route, resolvePath)
);
const activeModule = computed(() =>
  moduleOfItem(modules.value, activeItem.value)
);
const countOf = item => countOfItem(item, store.getters);
const countOfModule = module => moduleCount(module, store.getters);

// um módulo aberto por vez; ao trocar de tela, abre o módulo dela
const openModule = ref(null);
watch(
  () => activeModule.value?.name,
  name => {
    if (name) openModule.value = name;
  },
  { immediate: true }
);
// o destino ativo fica sempre à vista (ex.: Configurações > Segurança, lá embaixo)
const navRef = ref(null);
watch(activeItem, async () => {
  await nextTick();
  navRef.value
    ?.querySelector('.outsider-nav-leaf.active')
    ?.scrollIntoView({ block: 'nearest' });
});
const toggleModule = name => {
  openModule.value = openModule.value === name ? null : name;
};

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

const railWidth = computed(() =>
  isTablet.value || collapsed.value ? COLLAPSED_WIDTH : EXPANDED_WIDTH
);
const panelWidth = computed(() =>
  collapsed.value ? COLLAPSED_WIDTH : EXPANDED_WIDTH
);

// ---------- tema do menu ----------
// "Acompanhar o tema" usa as cores do Chatwoot (claro ou escuro); "Noite" deixa só o menu escuro,
// no preto Night (#141414) da identidade visual, como nas referências.
const isNight = computed(() => uiSettings.value?.outsider_nav_theme === 'night');
const themeClass = computed(() =>
  isNight.value ? 'dark outsider-nav--night' : ''
);
provide('outsiderNavThemeClass', themeClass);
const toggleTheme = () => {
  updateUISettings({ outsider_nav_theme: isNight.value ? 'auto' : 'night' });
};

const clickOutsideOptions = {
  ignore: ['[data-nav-flyout]', '[data-popover-content]'],
};
</script>

<template>
  <div
    class="relative h-full shrink-0 transition-[width] duration-200 ease-out"
    :style="{ width: `${railWidth}px` }"
    data-outsider-desktop-nav
  >
    <aside
      v-on-click-outside="[closeOverlay, clickOutsideOptions]"
      class="outsider-nav absolute inset-y-0 ltr:left-0 rtl:right-0 z-40 flex flex-col text-sm text-n-slate-12 bg-n-background ltr:border-r rtl:border-l border-n-weak transition-[width] duration-200 ease-out"
      :class="[
        themeClass,
        { 'shadow-2xl': isTablet && overlayOpen },
        collapsed ? 'outsider-nav--collapsed' : 'outsider-nav--expanded',
      ]"
      :style="{ width: `${panelWidth}px` }"
      :aria-label="t('OUTSIDER_NAV.LABEL')"
    >
      <!-- ===== topo: conta e recolher ===== -->
      <header
        class="flex shrink-0 gap-2"
        :class="
          collapsed
            ? 'flex-col items-center pt-3 pb-2'
            : 'items-center h-14 ps-3 pe-2'
        "
      >
        <template v-if="collapsed">
          <SidebarAccountSwitcher
            is-collapsed
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
        <template v-else>
          <span
            class="grid place-content-center shrink-0 size-8 rounded-lg bg-n-alpha-2"
          >
            <Logo class="size-5 rounded" />
          </span>
          <SidebarAccountSwitcher
            class="flex-1 min-w-0 -mx-1"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
        <button
          type="button"
          class="grid place-content-center shrink-0 size-8 rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
          :title="collapsed ? t('OUTSIDER_NAV.EXPAND') : t('OUTSIDER_NAV.COLLAPSE')"
          :aria-label="
            collapsed ? t('OUTSIDER_NAV.EXPAND') : t('OUTSIDER_NAV.COLLAPSE')
          "
          data-outsider-nav-toggle
          @click="toggleCollapsed"
        >
          <span
            class="size-[18px]"
            :class="
              collapsed ? 'i-lucide-panel-left-open' : 'i-lucide-panel-left-close'
            "
          />
        </button>
      </header>

      <!-- ===== buscar e nova conversa ===== -->
      <div
        class="flex shrink-0 gap-2"
        :class="collapsed ? 'flex-col items-center pb-2' : 'px-3 pb-3'"
      >
        <RouterLink
          :to="{ name: 'search' }"
          class="flex items-center gap-2 rounded-xl border border-n-weak bg-n-alpha-1 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
          :class="collapsed ? 'justify-center size-11' : 'flex-1 h-9 px-3 min-w-0'"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 shrink-0" />
          <template v-if="!collapsed">
            <span class="flex-1 min-w-0 truncate text-[13px]">
              {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
            </span>
            <kbd
              class="shrink-0 px-1.5 rounded-md border border-n-weak bg-n-solid-1 text-[10px] leading-4 font-sans text-n-slate-10"
            >
              {{ searchShortcut }}
            </kbd>
          </template>
        </RouterLink>
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              color="slate"
              size="sm"
              :title="t('OUTSIDER_NAV.NEW_CONVERSATION')"
              class="!bg-n-brand !text-white !rounded-xl !outline-0 hover:!brightness-110"
              :class="[
                collapsed ? '!size-11' : '!size-9',
                { '!brightness-110': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>

      <!-- ===== módulos por seção ===== -->
      <nav
        ref="navRef"
        class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden no-scrollbar pb-4"
        :class="collapsed ? 'px-2' : 'px-3'"
      >
        <section
          v-for="(section, index) in sections"
          :key="section.key"
          :data-nav-section="section.key"
        >
          <div
            v-if="collapsed && index > 0"
            class="mx-auto my-2 w-6 h-px bg-n-weak"
          />
          <h3
            v-else-if="!collapsed"
            class="m-0 px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-n-slate-9"
            :class="index === 0 ? 'pt-1' : 'pt-4'"
          >
            {{ t(section.label) }}
          </h3>
          <ul class="flex flex-col gap-0.5 m-0 p-0 min-w-0">
            <NavModule
              v-for="module in section.modules"
              :key="module.name"
              :module="module"
              :collapsed="collapsed"
              :open="openModule === module.name"
              :active-item="activeItem"
              :count="countOfModule(module)"
              :count-of="countOf"
              @toggle="toggleModule(module.name)"
            />
          </ul>
        </section>
      </nav>

      <!-- ===== rodapé: perfil, telefone e tema do menu ===== -->
      <footer
        class="flex shrink-0 gap-1 border-t border-n-weak"
        :class="
          collapsed ? 'flex-col items-center py-2' : 'items-center px-2 py-2'
        "
      >
        <div :class="collapsed ? '' : 'flex-1 min-w-0'">
          <SidebarProfileMenu
            :is-collapsed="collapsed"
            @open-key-shortcut-modal="emit('openKeyShortcutModal')"
          />
        </div>
        <OutsiderPhoneButton />
        <button
          type="button"
          class="grid place-content-center shrink-0 size-8 rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
          :title="isNight ? t('OUTSIDER_NAV.THEME_AUTO') : t('OUTSIDER_NAV.THEME_NIGHT')"
          :aria-label="
            isNight ? t('OUTSIDER_NAV.THEME_AUTO') : t('OUTSIDER_NAV.THEME_NIGHT')
          "
          data-outsider-nav-theme
          @click="toggleTheme"
        >
          <span
            class="size-4"
            :class="isNight ? 'i-lucide-sun-medium' : 'i-lucide-moon'"
          />
        </button>
      </footer>
    </aside>
  </div>
</template>
