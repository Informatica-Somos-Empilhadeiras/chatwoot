<script setup>
// OUTSIDER: um módulo do menu lateral (Conversas, CRM, Telefonia, Relatórios...).
// - Aberto: linha com a caixinha do ícone, o nome e a contagem (ou a seta); o módulo da tela atual
//   fica na pílula verde e, com opções, mostra a árvore logo abaixo.
// - Recolhido: só o ícone; passando o mouse (ou com o foco do teclado) abre um quadro ao lado com
//   as opções, e o clique leva direto à primeira (ou à que já está aberta).
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import NavGroups from './NavGroups.vue';
import NavFlyout from './NavFlyout.vue';
import { itemsOf } from '../navModel';
import { closeFlyout } from './navState';
import { useFlyout } from './useFlyout';
import { modulePill, shortCount } from './navCounts';

const props = defineProps({
  module: { type: Object, required: true },
  collapsed: { type: Boolean, default: false },
  open: { type: Boolean, default: false },
  // a tela atual é deste módulo (vale também para opções mostradas fora dele, como os Canais)
  activeHere: { type: Boolean, default: false },
  activeItem: { type: Object, default: null },
  count: { type: Number, default: 0 },
  countOf: { type: Function, required: true },
  // ícone no lugar do do Chatwoot (ex.: engrenagem nas Configurações)
  icon: { type: [String, Object, Function], default: null },
  // recolhido: o ícone dentro de um cartão (Configurações)
  boxed: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);

const { t } = useI18n();
const router = useRouter();

const hasGroups = computed(() => props.module.groups.length > 0);
const items = computed(() => itemsOf(props.module));
const shownIcon = computed(() => props.icon || props.module.icon);
const pill = computed(() => modulePill(props.module.name, props.count, t));

const go = to => to && router.push(to).catch(() => {});

const onRowClick = () => {
  if (!props.open && !props.activeHere) go(items.value[0]?.to);
  emit('toggle');
};

// ---------- recolhido: quadro ao lado ----------
const trigger = ref(null);
const { isOpen, show, hide, style } = useFlyout(
  computed(() => props.module.name),
  trigger
);

const onCollapsedClick = () => {
  const target =
    props.activeHere && items.value.includes(props.activeItem)
      ? props.activeItem
      : items.value[0];
  go(target?.to);
  if (!hasGroups.value) closeFlyout();
};
</script>

<template>
  <li class="onav-li" :data-nav-module="module.name">
    <!-- ===== menu recolhido ===== -->
    <template v-if="collapsed">
      <button
        ref="trigger"
        type="button"
        class="onav-ri"
        :class="{ on: activeHere, 'is-hover': isOpen, 'is-boxed': boxed }"
        :aria-label="module.label"
        :aria-expanded="hasGroups ? isOpen : undefined"
        @mouseenter="show"
        @mouseleave="hide()"
        @focus="show"
        @blur="hide()"
        @click="onCollapsedClick"
      >
        <span class="onav-ico">
          <Icon v-if="shownIcon" :icon="shownIcon" />
        </span>
        <span v-if="count" class="onav-corner">{{ shortCount(count) }}</span>
      </button>

      <NavFlyout
        v-if="isOpen"
        :name="module.name"
        :title="module.label"
        :icon="shownIcon"
        :fly-style="style"
      >
        <NavGroups
          v-if="hasGroups"
          :groups="module.groups"
          :active-item="activeItem"
          :count-of="countOf"
          variant="fly"
          @navigate="closeFlyout()"
        />
      </NavFlyout>
    </template>

    <!-- ===== menu aberto ===== -->
    <template v-else>
      <RouterLink
        v-if="!hasGroups"
        :to="module.to"
        class="onav-row"
        :class="{ on: activeHere }"
        :aria-current="activeHere ? 'page' : undefined"
      >
        <span class="onav-bx">
          <span class="onav-ico"><Icon v-if="shownIcon" :icon="shownIcon" /></span>
        </span>
        <span class="onav-label">{{ module.label }}</span>
        <span
          v-if="count"
          class="onav-pill"
          :class="{ 'onav-pill--soft': pill.soft && !activeHere }"
        >
          {{ pill.text }}
        </span>
      </RouterLink>

      <button
        v-else
        type="button"
        class="onav-row"
        :class="{ on: activeHere }"
        :aria-expanded="open"
        @click="onRowClick"
      >
        <span class="onav-bx">
          <span class="onav-ico"><Icon v-if="shownIcon" :icon="shownIcon" /></span>
        </span>
        <span class="onav-label">{{ module.label }}</span>
        <span
          v-if="count"
          class="onav-pill"
          :class="{ 'onav-pill--soft': pill.soft && !activeHere }"
        >
          {{ pill.text }}
        </span>
        <span
          v-else
          class="onav-chev"
          :class="open ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right is-closed'"
        />
      </button>

      <div v-if="hasGroups && open" class="onav-sub">
        <NavGroups
          :groups="module.groups"
          :active-item="activeItem"
          :count-of="countOf"
          variant="sub"
        />
      </div>
    </template>
  </li>
</template>
