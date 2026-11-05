<script setup>
// OUTSIDER: as opções de um módulo. As soltas (Todas, Menções...) ficam em lista; as que têm
// título (Canais, Pastas, Times, Etiquetas, Segmentos...) ficam num cartão que abre e fecha, com o
// total de não lidas no título quando fechado. Listas longas mostram as primeiras e "Ver todos".
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import NavLeaf from './NavLeaf.vue';
import { navState, isShowingAll, toggleShowAll } from './navState';

const props = defineProps({
  groups: { type: Array, required: true },
  activeItem: { type: Object, default: null },
  countOf: { type: Function, required: true },
});

const emit = defineEmits(['navigate']);

const LIMIT = 8;
const { t } = useI18n();

const hasActive = group => group.items.includes(props.activeItem);
// a escolha da pessoa vale; sem escolha, o grupo do destino ativo começa aberto
const opened = group => navState.groups[group.name] ?? hasActive(group);
const toggleGroup = group => {
  navState.groups[group.name] = !opened(group);
};
const groupCount = group =>
  group.items.reduce((sum, item) => sum + props.countOf(item), 0);

const shownItems = group => {
  if (isShowingAll(group.name) || group.items.length <= LIMIT + 1)
    return group.items;
  const first = group.items.slice(0, LIMIT);
  // o ativo sempre aparece, mesmo depois do limite
  if (props.activeItem && hasActive(group) && !first.includes(props.activeItem))
    first.push(props.activeItem);
  return first;
};
const hiddenCount = group => group.items.length - shownItems(group).length;
</script>

<template>
  <div class="flex flex-col gap-1.5 min-w-0">
    <template v-for="group in groups" :key="group.name">
      <ul v-if="!group.label" class="flex flex-col gap-0.5 m-0 p-0 min-w-0">
        <NavLeaf
          v-for="item in group.items"
          :key="item.name"
          :item="item"
          :active="item === activeItem"
          :count="countOf(item)"
          dense
          @navigate="emit('navigate')"
        />
      </ul>

      <section
        v-else
        class="min-w-0 rounded-xl border border-n-weak bg-n-alpha-1 dark:bg-n-alpha-2"
        :data-nav-group="group.name"
      >
        <button
          type="button"
          class="flex items-center w-full gap-2 h-8 px-2.5 rounded-xl text-[11px] font-semibold uppercase tracking-wider text-n-slate-10 hover:text-n-slate-12"
          :aria-expanded="opened(group)"
          @click="toggleGroup(group)"
        >
          <Icon
            v-if="typeof group.icon === 'string'"
            :icon="group.icon"
            class="size-3.5 shrink-0"
          />
          <span class="flex-1 min-w-0 truncate text-start">
            {{ group.label }}
          </span>
          <span
            v-if="!opened(group) && groupCount(group)"
            class="outsider-nav-badge shrink-0 normal-case tracking-normal"
          >
            {{ groupCount(group) > 99 ? '99+' : groupCount(group) }}
          </span>
          <span
            class="i-lucide-chevron-down size-3.5 shrink-0 transition-transform duration-150"
            :class="{ '-rotate-90 rtl:rotate-90': !opened(group) }"
          />
        </button>
        <ul
          v-if="opened(group)"
          class="flex flex-col gap-0.5 m-0 px-1 pb-1 min-w-0"
        >
          <NavLeaf
            v-for="item in shownItems(group)"
            :key="item.name"
            :item="item"
            :active="item === activeItem"
            :count="countOf(item)"
            dense
            @navigate="emit('navigate')"
          />
          <li
            v-if="hiddenCount(group) > 0 || isShowingAll(group.name)"
            class="list-none"
          >
            <button
              v-if="group.items.length > LIMIT + 1"
              type="button"
              class="w-full h-7 px-2.5 rounded-lg text-start text-xs text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
              @click="toggleShowAll(group.name)"
            >
              {{
                isShowingAll(group.name)
                  ? t('OUTSIDER_NAV.SHOW_LESS')
                  : t('OUTSIDER_NAV.SHOW_ALL', { count: group.items.length })
              }}
            </button>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>
