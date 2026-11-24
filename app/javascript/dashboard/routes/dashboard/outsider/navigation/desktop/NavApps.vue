<script setup>
// OUTSIDER: bloco de uma empresa na seção Aplicativos do menu aberto (Microsoft, Google): o logo e o nome da empresa,
// se a conta está conectada e a grade com o ícone de cada aplicativo e as não lidas. Com o menu recolhido o bloco vira
// um módulo comum (NavModule), com os aplicativos no quadro ao lado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { itemsOf } from '../navModel';
import { shortCount } from './navCounts';

const props = defineProps({
  module: { type: Object, required: true },
  activeItem: { type: Object, default: null },
  countOf: { type: Function, required: true },
});

const { t } = useI18n();
const items = computed(() => itemsOf(props.module));
const status = computed(() => props.module.appStatus || 'disconnected');
</script>

<template>
  <li class="onav-li" :data-nav-module="module.name">
    <div class="onav-apps">
      <div class="onav-apps-head">
        <span class="onav-ico onav-apps-logo"
          ><Icon :icon="module.icon"
        /></span>
        <span class="onav-label">{{ module.label }}</span>
        <span
          class="onav-apps-st"
          :class="`is-${status}`"
          :title="t(`OUTSIDER_APPS.STATUS.${status.toUpperCase()}`)"
        >
          <span class="onav-apps-dot" />
          {{ t(`OUTSIDER_APPS.STATUS.${status.toUpperCase()}`) }}
        </span>
      </div>
      <ul class="onav-apps-grid">
        <li v-for="item in items" :key="item.name">
          <RouterLink
            :to="item.to"
            class="onav-app"
            :class="{ on: activeItem === item }"
            :title="item.label"
            :aria-current="activeItem === item ? 'page' : undefined"
            :data-nav-app="item.name"
          >
            <span class="onav-app-ico"><Icon :icon="item.icon" /></span>
            <span class="onav-app-label">{{ item.label }}</span>
            <span v-if="countOf(item)" class="onav-app-badge">
              {{ shortCount(countOf(item)) }}
            </span>
          </RouterLink>
        </li>
      </ul>
    </div>
  </li>
</template>
