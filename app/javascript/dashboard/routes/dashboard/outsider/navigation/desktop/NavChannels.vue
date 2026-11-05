<script setup>
// OUTSIDER: os Canais (caixas de entrada) num bloco próprio, logo depois de Conversas.
// - Aberto: título "Canais" com o atalho para configurar os canais e um cartão com o logo de cada
//   canal (WhatsApp, site, e-mail...), o nome e as não lidas. Muitos canais: os primeiros e "Ver todos".
// - Recolhido: os logos num cartão logo abaixo do ícone de Conversas; os que não cabem ficam no "+N",
//   que abre o quadro ao lado com todos.
// Os itens vêm do grupo "Channels" do menu de Conversas do Chatwoot (menuItems do Sidebar.vue).
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { channelBadge } from 'dashboard/helper/outsider/channelBadge';
import NavFlyout from './NavFlyout.vue';
import { closeFlyout, isShowingAll, toggleShowAll } from './navState';
import { useFlyout } from './useFlyout';
import { shortCount } from './navCounts';

const props = defineProps({
  group: { type: Object, required: true },
  collapsed: { type: Boolean, default: false },
  activeItem: { type: Object, default: null },
  countOf: { type: Function, required: true },
  // Configurações > Caixas de entrada, quando a pessoa pode abrir
  manageTo: { type: Object, default: null },
});

const LIMIT = 6;
const RAIL_LIMIT = 4;

const { t } = useI18n();
const store = useStore();

const inboxOf = item => {
  const id = Number(item.to?.params?.inbox_id);
  return id ? store.getters['inboxes/getInbox'](id) : null;
};

const channels = computed(() =>
  props.group.items.map(item => {
    const badge = channelBadge(inboxOf(item)) || channelBadge({});
    const white = badge?.kind === 'whatsapp';
    return {
      item,
      icon: badge?.icon || 'i-lucide-inbox',
      white,
      style: white
        ? { background: '#fff', color: badge.color }
        : { background: badge?.color || '#64748B', color: '#fff' },
    };
  })
);

const isActive = channel => channel.item === props.activeItem;

const limited = (list, limit) => {
  if (list.length <= limit + 1) return list;
  const first = list.slice(0, limit);
  const active = list.find(isActive);
  if (active && !first.includes(active)) first.push(active);
  return first;
};

const showAll = computed(() => isShowingAll(props.group.name));
const shown = computed(() =>
  showAll.value ? channels.value : limited(channels.value, LIMIT)
);
const canShowAll = computed(() => channels.value.length > LIMIT + 1);

const railShown = computed(() => limited(channels.value, RAIL_LIMIT));
const railHidden = computed(
  () => channels.value.length - railShown.value.length
);

// recolhido: o "+N" abre o quadro com todos os canais
const moreRef = ref(null);
const {
  isOpen: isFlyoutOpen,
  show,
  hide,
  style,
} = useFlyout('Channels', moreRef);
</script>

<template>
  <!-- ===== recolhido ===== -->
  <li v-if="collapsed" class="onav-li" data-nav-group="Channels">
    <div class="onav-grp">
      <RouterLink
        v-for="channel in railShown"
        :key="channel.item.name"
        v-tooltip.right="channel.item.label"
        :to="channel.item.to"
        class="onav-grp-it"
        :class="{ on: isActive(channel) }"
        :aria-label="channel.item.label"
        :aria-current="isActive(channel) ? 'page' : undefined"
      >
        <span
          class="onav-logo"
          :class="{ 'is-white': channel.white }"
          :style="channel.style"
        >
          <span :class="channel.icon" />
        </span>
        <span v-if="countOf(channel.item)" class="onav-corner">
          {{ shortCount(countOf(channel.item)) }}
        </span>
      </RouterLink>
      <button
        v-if="railHidden > 0"
        ref="moreRef"
        type="button"
        class="onav-grp-it onav-grp-more"
        :aria-label="group.label"
        :aria-expanded="isFlyoutOpen"
        @mouseenter="show"
        @mouseleave="hide()"
        @focus="show"
        @click="show"
      >
        +{{ railHidden }}
      </button>
    </div>
    <NavFlyout
      v-if="isFlyoutOpen"
      name="Channels"
      :title="group.label"
      icon="i-lucide-mailbox"
      :fly-style="style"
    >
      <ul class="onav-card">
        <li v-for="channel in channels" :key="channel.item.name" class="onav-li">
          <RouterLink
            :to="channel.item.to"
            class="onav-ch"
            :class="{ on: isActive(channel) }"
            @click="closeFlyout()"
          >
            <span
              class="onav-logo"
              :class="{ 'is-white': channel.white }"
              :style="channel.style"
            >
              <span :class="channel.icon" />
            </span>
            <span class="onav-label">{{ channel.item.label }}</span>
            <span v-if="countOf(channel.item)" class="onav-pill onav-pill--sm">
              {{ shortCount(countOf(channel.item)) }}
            </span>
          </RouterLink>
        </li>
      </ul>
    </NavFlyout>
  </li>

  <!-- ===== aberto ===== -->
  <li v-else class="onav-li onav-block" data-nav-group="Channels">
    <div class="onav-hh">
      <span>{{ group.label }}</span>
      <RouterLink
        v-if="manageTo"
        v-tooltip.top="t('OUTSIDER_NAV.MANAGE_CHANNELS')"
        :to="manageTo"
        class="onav-hh-btn"
        :aria-label="t('OUTSIDER_NAV.MANAGE_CHANNELS')"
      >
        <span class="i-lucide-sliders-horizontal size-3.5" />
      </RouterLink>
    </div>
    <ul class="onav-card">
      <li v-for="channel in shown" :key="channel.item.name" class="onav-li">
        <RouterLink
          :to="channel.item.to"
          :title="channel.item.label"
          class="onav-ch"
          :class="{ on: isActive(channel) }"
          :aria-current="isActive(channel) ? 'page' : undefined"
        >
          <span
            class="onav-logo"
            :class="{ 'is-white': channel.white }"
            :style="channel.style"
          >
            <span :class="channel.icon" />
          </span>
          <span class="onav-label">{{ channel.item.label }}</span>
          <span v-if="countOf(channel.item)" class="onav-pill onav-pill--sm">
            {{ shortCount(countOf(channel.item)) }}
          </span>
        </RouterLink>
      </li>
      <li v-if="canShowAll" class="onav-li">
        <button
          type="button"
          class="onav-more"
          @click="toggleShowAll(group.name)"
        >
          {{
            showAll
              ? t('OUTSIDER_NAV.SHOW_LESS')
              : t('OUTSIDER_NAV.SHOW_ALL', { count: channels.length })
          }}
        </button>
      </li>
    </ul>
  </li>
</template>
