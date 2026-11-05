<script setup>
// OUTSIDER: as Configurações no fim do menu, num bloco próprio.
// - Aberto: título com a engrenagem (abre e fecha a lista completa) e uma fileira com os atalhos mais
//   usados (Conta, Agentes, Caixas de entrada, Etiquetas, Automação, Integrações).
// - Recolhido: a engrenagem num cartão; passando o mouse, o quadro ao lado com todas as opções.
// Só aparecem as opções que a pessoa pode abrir (o módulo já vem filtrado pelo navModel).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import NavGroups from './NavGroups.vue';
import NavModule from './NavModule.vue';
import { itemsOf } from '../navModel';
import { navState } from './navState';

const props = defineProps({
  module: { type: Object, required: true },
  collapsed: { type: Boolean, default: false },
  activeHere: { type: Boolean, default: false },
  activeItem: { type: Object, default: null },
  countOf: { type: Function, required: true },
});

const SHORTCUTS = [
  'Settings Account Settings',
  'Settings Agents',
  'Settings Inboxes',
  'Settings Labels',
  'Settings Automation',
  'Settings Integrations',
];
const MAX_SHORTCUTS = 6;
const STATE_KEY = 'SettingsAll';

const { t } = useI18n();

const items = computed(() => itemsOf(props.module));
const shortcuts = computed(() => {
  const withIcon = items.value.filter(item => typeof item.icon === 'string');
  const preferred = SHORTCUTS.map(name =>
    withIcon.find(item => item.name === name)
  ).filter(Boolean);
  const rest = withIcon.filter(item => !preferred.includes(item));
  return [...preferred, ...rest].slice(0, MAX_SHORTCUTS);
});
const hasMore = computed(() => items.value.length > shortcuts.value.length);

// a lista completa abre sozinha quando a tela atual é uma opção que não está nos atalhos
const listOpen = computed(
  () =>
    navState.groups[STATE_KEY] ??
    (props.activeHere && !shortcuts.value.includes(props.activeItem))
);
const toggleList = () => {
  navState.groups[STATE_KEY] = !listOpen.value;
};
</script>

<template>
  <NavModule
    v-if="collapsed"
    :module="module"
    collapsed
    boxed
    icon="i-lucide-settings"
    :active-here="activeHere"
    :active-item="activeItem"
    :count-of="countOf"
  />

  <li v-else class="onav-li onav-block" data-nav-module="Settings">
    <div class="onav-hh">
      <span>{{ module.label }}</span>
      <button
        v-if="hasMore"
        v-tooltip.top="
          listOpen ? t('OUTSIDER_NAV.SETTINGS_LESS') : t('OUTSIDER_NAV.SETTINGS_ALL')
        "
        type="button"
        class="onav-hh-btn"
        :class="{ 'is-on': listOpen }"
        :aria-expanded="listOpen"
        :aria-label="t('OUTSIDER_NAV.SETTINGS_ALL')"
        @click="toggleList"
      >
        <span class="i-lucide-settings size-3.5" />
      </button>
    </div>
    <div class="onav-card onav-icons">
      <RouterLink
        v-for="item in shortcuts"
        :key="item.name"
        v-tooltip.top="item.label"
        :to="item.to"
        class="onav-ic"
        :class="{ on: item === activeItem }"
        :aria-label="item.label"
        :aria-current="item === activeItem ? 'page' : undefined"
      >
        <span class="onav-ico"><Icon :icon="item.icon" /></span>
      </RouterLink>
    </div>
    <div v-if="hasMore && listOpen" class="onav-card">
      <NavGroups
        :groups="module.groups"
        :active-item="activeItem"
        :count-of="countOf"
        variant="fly"
      />
    </div>
  </li>
</template>
