<script setup>
// OUTSIDER: um módulo do menu lateral (Conversas, CRM, Telefonia, Relatórios...).
// - Aberto: linha com ícone, nome e contagem; com seções, abre e fecha as opções logo abaixo.
// - Recolhido: só o ícone; passando o mouse (ou com o foco do teclado) abre um quadro ao lado com
//   as opções, e o clique leva direto à primeira (ou à que já está aberta).
import { computed, inject, nextTick, ref } from 'vue';
import { useRouter } from 'vue-router';
import Icon from 'next/icon/Icon.vue';
import NavGroups from './NavGroups.vue';
import { itemsOf } from '../navModel';
import { flyout, openFlyout, closeFlyout, keepFlyout } from './navState';

const props = defineProps({
  module: { type: Object, required: true },
  collapsed: { type: Boolean, default: false },
  open: { type: Boolean, default: false },
  activeItem: { type: Object, default: null },
  count: { type: Number, default: 0 },
  countOf: { type: Function, required: true },
});

const emit = defineEmits(['toggle']);

const router = useRouter();
const themeClass = inject('outsiderNavThemeClass', ref(''));

const hasGroups = computed(() => props.module.groups.length > 0);
const items = computed(() => itemsOf(props.module));
const containsActive = computed(
  () => !!props.activeItem && items.value.includes(props.activeItem)
);
// destino único ativo: pílula verde; módulo com a opção ativa dentro: nome e ícone em verde
const isActiveLink = computed(() => !hasGroups.value && containsActive.value);

const go = to => to && router.push(to).catch(() => {});

const onRowClick = () => {
  if (!hasGroups.value) return;
  if (!props.open && !containsActive.value) go(items.value[0]?.to);
  emit('toggle');
};

// ---------- recolhido: quadro ao lado ----------
const trigger = ref(null);
const position = ref({ top: 0, left: 0 });
const isFlyoutOpen = computed(() => flyout.name === props.module.name);

const showFlyout = async () => {
  const rect = trigger.value?.getBoundingClientRect();
  if (!rect) return;
  const rtl = document.documentElement.dir === 'rtl';
  position.value = {
    top: Math.max(8, rect.top - 6),
    left: rtl ? undefined : rect.right + 10,
    right: rtl ? window.innerWidth - rect.left + 10 : undefined,
  };
  openFlyout(props.module.name);
  await nextTick();
  // não deixa o quadro passar do fim da tela
  const panel = document.querySelector(
    `[data-nav-flyout="${props.module.name}"]`
  );
  if (!panel) return;
  const overflow = panel.getBoundingClientRect().bottom - window.innerHeight;
  if (overflow > 0)
    position.value = {
      ...position.value,
      top: Math.max(8, position.value.top - overflow - 8),
    };
};

const onCollapsedClick = () => {
  const target = containsActive.value ? props.activeItem : items.value[0];
  go(target?.to);
  if (!hasGroups.value) closeFlyout();
};

const flyoutStyle = computed(() => ({
  top: `${position.value.top}px`,
  ...(position.value.left !== undefined
    ? { left: `${position.value.left}px` }
    : { right: `${position.value.right}px` }),
}));
</script>

<template>
  <li class="min-w-0 list-none" :data-nav-module="module.name">
    <!-- ===== menu recolhido ===== -->
    <template v-if="collapsed">
      <button
        ref="trigger"
        type="button"
        class="relative grid place-content-center mx-auto size-11 rounded-xl transition-colors duration-100"
        :class="
          containsActive
            ? 'bg-n-brand text-white shadow-sm'
            : isFlyoutOpen
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-label="module.label"
        :aria-expanded="hasGroups ? isFlyoutOpen : undefined"
        @mouseenter="showFlyout"
        @mouseleave="closeFlyout(180)"
        @focus="showFlyout"
        @blur="closeFlyout(180)"
        @click="onCollapsedClick"
      >
        <span class="grid place-content-center size-5 [&>*]:size-5">
          <Icon v-if="module.icon" :icon="module.icon" class="size-5" />
        </span>
        <span
          v-if="count"
          class="outsider-nav-badge outsider-nav-badge--corner absolute -top-0.5 ltr:-right-0.5 rtl:-left-0.5"
        >
          {{ count > 99 ? '99+' : count }}
        </span>
      </button>

      <Teleport to="body">
        <div
          v-if="isFlyoutOpen"
          class="outsider-nav-flyout fixed z-[60] w-64 max-h-[calc(100vh-1rem)] overflow-y-auto no-scrollbar rounded-2xl border border-n-weak bg-n-solid-2 p-2 shadow-xl text-n-slate-12"
          :class="themeClass"
          :style="flyoutStyle"
          :data-nav-flyout="module.name"
          @mouseenter="keepFlyout"
          @mouseleave="closeFlyout(120)"
        >
          <div
            class="flex items-center gap-2 px-2.5 pt-1 pb-2 text-sm font-semibold text-n-slate-12"
          >
            <span>{{ module.label }}</span>
            <span v-if="count" class="outsider-nav-badge">{{ count }}</span>
          </div>
          <NavGroups
            v-if="hasGroups"
            :groups="module.groups"
            :active-item="activeItem"
            :count-of="countOf"
            @navigate="closeFlyout()"
          />
        </div>
      </Teleport>
    </template>

    <!-- ===== menu aberto ===== -->
    <template v-else>
      <RouterLink
        v-if="!hasGroups"
        :to="module.to"
        class="flex items-center gap-3 h-10 px-3 rounded-xl text-sm transition-colors duration-100 min-w-0"
        :class="
          isActiveLink
            ? 'bg-n-brand text-white font-medium shadow-sm'
            : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
      >
        <span
          class="grid place-content-center size-[18px] shrink-0 [&>*]:size-[18px]"
        >
          <Icon v-if="module.icon" :icon="module.icon" class="size-[18px]" />
        </span>
        <span class="flex-1 min-w-0 truncate">{{ module.label }}</span>
        <span
          v-if="count"
          class="outsider-nav-badge shrink-0"
          :class="{ 'outsider-nav-badge--on-brand': isActiveLink }"
        >
          {{ count > 99 ? '99+' : count }}
        </span>
      </RouterLink>

      <button
        v-else
        type="button"
        class="relative flex items-center w-full gap-3 h-10 px-3 rounded-xl text-sm transition-colors duration-100 min-w-0"
        :class="
          containsActive
            ? 'text-n-slate-12 font-semibold'
            : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-expanded="open"
        @click="onRowClick"
      >
        <span
          v-if="containsActive"
          class="absolute inset-y-2 w-[3px] rounded-full bg-n-brand ltr:-left-2 rtl:-right-2"
        />
        <span
          class="grid place-content-center size-[18px] shrink-0 [&>*]:size-[18px]"
          :class="{ 'outsider-nav-brand-text': containsActive }"
        >
          <Icon v-if="module.icon" :icon="module.icon" class="size-[18px]" />
        </span>
        <span class="flex-1 min-w-0 truncate text-start">{{
          module.label
        }}</span>
        <span v-if="count && !open" class="outsider-nav-badge shrink-0">
          {{ count > 99 ? '99+' : count }}
        </span>
        <span
          class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-10 transition-transform duration-150"
          :class="{ '-rotate-90 rtl:rotate-90': !open }"
        />
      </button>

      <div
        v-if="hasGroups && open"
        class="mt-1 mb-2 ms-[1.3rem] ps-2.5 border-s border-n-weak min-w-0"
      >
        <NavGroups
          :groups="module.groups"
          :active-item="activeItem"
          :count-of="countOf"
        />
      </div>
    </template>
  </li>
</template>
