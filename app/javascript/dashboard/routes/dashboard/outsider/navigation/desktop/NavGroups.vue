<script setup>
// OUTSIDER: as opções de um módulo. As soltas (Todas, Menções...) ficam em lista; as que têm título
// (Pastas, Times, Etiquetas, Segmentos...) ficam num grupo que abre e fecha, com o total de não lidas
// no título quando fechado. Listas longas mostram as primeiras e "Ver todos".
// variant: "sub" (árvore do módulo aberto) ou "fly" (quadro do recolhido e lista das Configurações).
import { useI18n } from 'vue-i18n';
import NavLeaf from './NavLeaf.vue';
import { navState, isShowingAll, toggleShowAll } from './navState';
import { shortCount } from './navCounts';

const props = defineProps({
  groups: { type: Array, required: true },
  activeItem: { type: Object, default: null },
  countOf: { type: Function, required: true },
  variant: { type: String, default: 'sub' },
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
const canShowAll = group => group.items.length > LIMIT + 1;
</script>

<template>
  <div class="onav-groups flex flex-col min-w-0">
    <template v-for="group in groups" :key="group.name">
      <ul v-if="!group.label" class="onav-gl">
        <NavLeaf
          v-for="item in group.items"
          :key="item.name"
          :item="item"
          :active="item === activeItem"
          :count="countOf(item)"
          :variant="variant"
          @navigate="emit('navigate')"
        />
      </ul>

      <section v-else class="min-w-0" :data-nav-group="group.name">
        <button
          type="button"
          class="onav-gh"
          :aria-expanded="opened(group)"
          @click="toggleGroup(group)"
        >
          <span class="onav-label">{{ group.label }}</span>
          <span
            v-if="!opened(group) && groupCount(group)"
            class="onav-pill onav-pill--sm"
          >
            {{ shortCount(groupCount(group)) }}
          </span>
          <span
            class="onav-chev"
            :class="
              opened(group) ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right is-closed'
            "
          />
        </button>
        <ul v-if="opened(group)" class="onav-gl">
          <NavLeaf
            v-for="item in shownItems(group)"
            :key="item.name"
            :item="item"
            :active="item === activeItem"
            :count="countOf(item)"
            :variant="variant"
            @navigate="emit('navigate')"
          />
          <li v-if="canShowAll(group)" class="onav-li">
            <button
              type="button"
              class="onav-more"
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
