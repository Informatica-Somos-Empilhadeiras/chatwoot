<script setup>
// OUTSIDER: barra de navegação de baixo no celular (abaixo de 768 px), no lugar do menu lateral.
// Usa os mesmos itens do menu lateral do Chatwoot (Sidebar.vue passa o menuItems), com as mesmas
// permissões, então tudo que aparece no menu aparece aqui, e o que some lá some aqui.
//
// Hierarquia pensada para chegar em qualquer tela com no máximo 3 toques:
// - 4 módulos fixos (Conversas, CRM, Telefonia, Contatos; os que a pessoa não tem dão a vez aos
//   próximos) e "Mais" com o resto (Caixa de entrada, Status, Relatórios, Configurações...).
// - Conversas abre a lista direto (1 toque). Já na lista, tocar de novo em Conversas abre, logo
//   acima do botão, os filtros e os canais (2 toques para trocar de canal).
// - Módulo com várias seções (CRM, Telefonia, Contatos) abre as seções logo acima do botão.
// - Em "Mais", um módulo com seções abre as seções no mesmo quadro (Mais > Relatórios > Visão geral).
// A barra some com uma conversa aberta (a conversa usa a tela toda, como no WhatsApp) e com o
// teclado aberto.
import { computed, ref, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useEventListener, useWindowSize } from '@vueuse/core';
import { useStore } from 'vuex';
import { useSidebarContext } from 'dashboard/components-next/sidebar/provider';
import { phone, setPanelOpen } from '../voice/phone';
import { SMALL_SCREEN, viewportState } from './screen';
import {
  renderIcon,
  makeAllowed,
  toModules,
  itemsOf,
  countOf as countOfItem,
  moduleCount as moduleCountOf,
} from '../navigation/navModel';

const props = defineProps({
  menuItems: { type: Array, default: () => [] },
});

const PRIMARY = ['Conversation', 'OutsiderCrm', 'OutsiderVoice', 'Contacts'];
const PRIMARY_SLOTS = 4;
const CONVERSATION = 'Conversation';
// telas que são a conversa aberta ou janelas próprias: sem barra
const HIDDEN_ROUTES = ['outsider_phone_window', 'inbox_view_conversation'];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { isAllowed, resolvePath } = useSidebarContext();
const { width } = useWindowSize();

const allowed = makeAllowed(isAllowed);

const modules = computed(() => toModules(props.menuItems, allowed));

const primaryModules = computed(() => {
  const list = PRIMARY.map(name =>
    modules.value.find(m => m.name === name)
  ).filter(Boolean);
  modules.value.forEach(m => {
    if (list.length < PRIMARY_SLOTS && !list.includes(m)) list.push(m);
  });
  return list;
});
const moreModules = computed(() =>
  modules.value.filter(m => !primaryModules.value.includes(m))
);

const isItemActive = item => {
  if (!item.to) return false;
  if (item.activeOn?.includes(route.name)) return true;
  const path = resolvePath(item.to);
  return route.path === path || route.path.startsWith(`${path}/`);
};
const isModuleActive = module => itemsOf(module).some(isItemActive);
const activeModule = computed(
  () =>
    primaryModules.value.find(isModuleActive) ||
    (moreModules.value.some(isModuleActive) ? 'more' : null)
);

const countOf = item => countOfItem(item, store.getters);
const moduleCount = module => moduleCountOf(module, store.getters);

// ---------- quadro de opções acima do botão ----------
const sheet = ref(null); // { anchor, title, groups, back, actions }
const buttons = ref({});
const sheetRef = ref(null);
const sheetStyle = ref({});
const arrowLeft = ref(0);

const closeSheet = () => {
  sheet.value = null;
};

const place = async () => {
  await nextTick();
  const button = buttons.value[sheet.value?.anchor];
  const panel = sheetRef.value;
  if (!button || !panel) return;
  const rect = button.getBoundingClientRect();
  const panelWidth = panel.offsetWidth;
  const center = rect.left + rect.width / 2;
  const left = Math.min(
    Math.max(8, center - panelWidth / 2),
    window.innerWidth - panelWidth - 8
  );
  sheetStyle.value = { left: `${left}px` };
  arrowLeft.value = Math.min(Math.max(16, center - left), panelWidth - 16);
};

const openSheet = value => {
  sheet.value = value;
  place();
};

const phoneAction = () =>
  phone.status !== 'off'
    ? [
        {
          key: 'phone',
          label: t('OUTSIDER_RESPONSIVE.OPEN_PHONE'),
          icon: 'i-lucide-phone-call',
          run: () => setPanelOpen(true),
        },
      ]
    : [];

const moduleSheet = (module, anchor, back = null) => ({
  anchor,
  title: module.label,
  groups: module.groups,
  back,
  actions: module.name === 'OutsiderVoice' ? phoneAction() : [],
});

const go = to => {
  closeSheet();
  if (to) router.push(to).catch(() => {});
};

const conversationHome = module => module.groups[0]?.items[0]?.to;

const onTab = module => {
  if (sheet.value?.anchor === module.name) {
    closeSheet();
    return;
  }
  if (module.to) {
    go(module.to);
    return;
  }
  // Conversas: primeiro toque abre a lista; com a lista já aberta, abre canais e filtros
  if (module.name === CONVERSATION && activeModule.value !== module) {
    go(conversationHome(module));
    return;
  }
  const items = itemsOf(module);
  if (
    items.length === 1 &&
    !(module.name === 'OutsiderVoice' && phoneAction().length)
  ) {
    go(items[0].to);
    return;
  }
  openSheet(moduleSheet(module, module.name));
};

// o menu lateral inteiro (troca de conta, perfil, sair) continua a um toque, pelo botão do Chatwoot
const openFullMenu = () => {
  document.querySelector('#mobile-sidebar-launcher button')?.click();
};

const moreSheet = () => ({
  anchor: 'more',
  title: t('OUTSIDER_RESPONSIVE.MORE'),
  groups: [
    {
      name: 'more',
      label: '',
      items: moreModules.value.map(m => ({ ...m, module: m })),
    },
  ],
  back: null,
  actions: [
    {
      key: 'menu',
      label: t('OUTSIDER_RESPONSIVE.FULL_MENU'),
      icon: 'i-lucide-panel-left-open',
      run: openFullMenu,
    },
  ],
});

const onMore = () => {
  if (sheet.value?.anchor === 'more') {
    closeSheet();
    return;
  }
  openSheet(moreSheet());
};

const onSheetItem = item => {
  const module = item.module;
  if (!module) {
    go(item.to);
    return;
  }
  if (module.to) {
    go(module.to);
    return;
  }
  const items = itemsOf(module);
  if (items.length === 1) {
    go(items[0].to);
    return;
  }
  openSheet(moduleSheet(module, 'more', moreSheet()));
};

const onAction = action => {
  closeSheet();
  action.run();
};

// ---------- quando a barra aparece ----------

const visible = computed(
  () =>
    width.value < SMALL_SCREEN &&
    !route.params.conversation_id &&
    !HIDDEN_ROUTES.includes(route.name) &&
    !viewportState.keyboardOpen &&
    primaryModules.value.length > 0
);

watch(() => route.fullPath, closeSheet);
watch(visible, value => {
  if (!value) closeSheet();
});
useEventListener(window, 'keydown', event => {
  if (event.key === 'Escape') closeSheet();
});
useEventListener(window, 'resize', () => sheet.value && place());

// só um botão fica "aberto" (ícone + nome): o do quadro aberto ou, sem quadro, o da tela atual
const highlighted = computed(() => {
  if (sheet.value) return sheet.value.anchor;
  if (activeModule.value === 'more') return 'more';
  return activeModule.value?.name || null;
});

const setButton = (name, el) => {
  if (el) buttons.value[name] = el;
};
</script>

<template>
  <Teleport to="body">
    <template v-if="visible">
      <div
        v-if="sheet"
        class="fixed inset-0 z-[45] bg-n-alpha-black1/40 backdrop-blur-[1px]"
        data-outsider-tabbar-backdrop
        @click="closeSheet"
      />
      <div
        v-if="sheet"
        ref="sheetRef"
        class="fixed z-[46] w-[min(20rem,calc(100vw-1rem))] bottom-[calc(4.75rem+env(safe-area-inset-bottom))] flex flex-col max-h-[min(70vh,calc(var(--outsider-app-height,100dvh)-7rem))] rounded-2xl border border-n-weak bg-n-solid-1 shadow-2xl outsider-tabbar-sheet"
        :style="sheetStyle"
        role="menu"
        data-outsider-tabbar-sheet
      >
        <div class="flex items-center gap-1 px-2 pt-2 pb-1 shrink-0">
          <button
            v-if="sheet.back"
            type="button"
            class="grid place-content-center rounded-full size-8 text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('OUTSIDER_RESPONSIVE.BACK')"
            @click="openSheet(sheet.back)"
          >
            <span class="i-lucide-chevron-left size-5" />
          </button>
          <span
            class="flex-1 min-w-0 px-2 text-xs font-semibold tracking-wide uppercase truncate text-n-slate-10"
          >
            {{ sheet.title }}
          </span>
        </div>
        <div
          class="flex flex-col min-h-0 gap-1 px-2 pb-2 overflow-y-auto overscroll-contain"
        >
          <button
            v-for="action in sheet.actions.filter(a => a.key !== 'menu')"
            :key="action.key"
            type="button"
            role="menuitem"
            class="flex items-center gap-3 px-3 text-sm font-semibold text-white rounded-xl h-11 shrink-0 bg-n-brand active:brightness-110"
            @click="onAction(action)"
          >
            <span :class="action.icon" class="size-5 shrink-0" />
            <span class="truncate">{{ action.label }}</span>
          </button>
          <template v-for="group in sheet.groups" :key="group.name">
            <div
              v-if="group.label"
              class="flex items-center gap-2 px-3 pt-2 pb-1 text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ group.label }}
            </div>
            <button
              v-for="item in group.items"
              :key="item.name"
              type="button"
              role="menuitem"
              class="flex items-center gap-3 px-3 text-sm text-left rounded-xl min-h-11 shrink-0 text-n-slate-12 active:bg-n-alpha-3"
              :class="
                isItemActive(item) ||
                (item.module && isModuleActive(item.module))
                  ? 'bg-n-brand/10 text-n-brand font-semibold dark:text-n-slate-12'
                  : 'hover:bg-n-alpha-2'
              "
              @click="onSheetItem(item)"
            >
              <span
                class="grid size-5 shrink-0 place-content-center text-n-slate-11 [&_span]:size-[18px]"
              >
                <component :is="renderIcon(item.icon)" v-if="item.icon" />
                <span v-else class="rounded-full !size-1.5 bg-n-slate-8" />
              </span>
              <span class="flex-1 min-w-0 py-2 truncate">{{ item.label }}</span>
              <span
                v-if="
                  (item.module ? moduleCount(item.module) : countOf(item)) > 0
                "
                class="inline-grid place-items-center h-5 min-w-5 px-1.5 rounded-full text-[11px] font-bold leading-none outsider-brand-badge"
              >
                {{ item.module ? moduleCount(item.module) : countOf(item) }}
              </span>
              <span
                v-if="
                  item.module &&
                  !item.module.to &&
                  itemsOf(item.module).length > 1
                "
                class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-10"
              />
            </button>
          </template>
          <button
            v-for="action in sheet.actions.filter(a => a.key === 'menu')"
            :key="action.key"
            type="button"
            role="menuitem"
            class="flex items-center gap-3 px-3 mt-1 text-sm border-t rounded-none h-11 shrink-0 text-n-slate-11 border-n-weak"
            @click="onAction(action)"
          >
            <span :class="action.icon" class="size-5 shrink-0" />
            <span class="truncate">{{ action.label }}</span>
          </button>
        </div>
        <span
          class="absolute -bottom-[7px] size-3.5 rotate-45 border-b border-r border-n-weak bg-n-solid-1"
          :style="{ left: `${arrowLeft - 7}px` }"
        />
      </div>

      <nav
        class="fixed inset-x-0 bottom-0 z-[46] px-2 pt-1.5 pb-[max(0.5rem,env(safe-area-inset-bottom))] pointer-events-none"
        :aria-label="t('OUTSIDER_RESPONSIVE.NAVIGATION')"
        data-outsider-tabbar
      >
        <div
          class="flex items-center justify-around h-16 gap-1 px-1.5 mx-auto border shadow-lg pointer-events-auto max-w-md rounded-[1.375rem] border-n-weak bg-n-solid-1/95 backdrop-blur-md"
        >
          <button
            v-for="module in primaryModules"
            :key="module.name"
            :ref="el => setButton(module.name, el)"
            type="button"
            class="relative flex items-center justify-center min-w-0 gap-1.5 rounded-full h-11 transition-all duration-200 ease-out"
            :class="
              highlighted === module.name
                ? 'px-4 bg-n-brand/10 text-n-brand dark:bg-n-brand/30 dark:text-n-slate-12 flex-auto max-w-[11rem]'
                : 'w-12 flex-none text-n-slate-11 active:bg-n-alpha-2'
            "
            :aria-label="module.label"
            :aria-current="activeModule === module ? 'page' : undefined"
            :aria-expanded="sheet?.anchor === module.name"
            @click="onTab(module)"
          >
            <span
              class="grid shrink-0 size-6 place-content-center [&>span]:size-[22px] [&_svg]:size-[22px]"
            >
              <component :is="renderIcon(module.icon)" />
            </span>
            <span
              v-if="highlighted === module.name"
              class="text-[13px] font-semibold truncate"
            >
              {{ module.label }}
            </span>
            <span
              v-if="
                module.name === 'Conversation' &&
                activeModule === module &&
                !sheet
              "
              class="i-lucide-chevron-up size-3.5 shrink-0 opacity-70"
            />
            <span
              v-if="moduleCount(module) > 0"
              class="absolute top-1 ltr:right-[calc(50%-1.1rem)] rtl:left-[calc(50%-1.1rem)] size-2.5 rounded-full ring-2 ring-n-solid-1 outsider-brand-dot"
              :class="{ hidden: highlighted === module.name }"
            />
          </button>
          <button
            v-if="moreModules.length"
            :ref="el => setButton('more', el)"
            type="button"
            class="relative flex items-center justify-center min-w-0 gap-1.5 rounded-full h-11 transition-all duration-200 ease-out"
            :class="
              highlighted === 'more'
                ? 'px-4 bg-n-brand/10 text-n-brand dark:bg-n-brand/30 dark:text-n-slate-12 flex-auto max-w-[11rem]'
                : 'w-12 flex-none text-n-slate-11 active:bg-n-alpha-2'
            "
            :aria-label="t('OUTSIDER_RESPONSIVE.MORE')"
            :aria-expanded="sheet?.anchor === 'more'"
            @click="onMore"
          >
            <span class="i-lucide-layout-grid size-[22px] shrink-0" />
            <span
              v-if="highlighted === 'more'"
              class="text-[13px] font-semibold truncate"
            >
              {{ t('OUTSIDER_RESPONSIVE.MORE') }}
            </span>
            <span
              v-if="moreModules.some(m => moduleCount(m) > 0)"
              class="absolute top-1 ltr:right-[calc(50%-1.1rem)] rtl:left-[calc(50%-1.1rem)] size-2.5 rounded-full ring-2 ring-n-solid-1 outsider-brand-dot"
            />
          </button>
        </div>
      </nav>
    </template>
  </Teleport>
</template>
