<script setup>
// OUTSIDER: um destino do menu lateral (ex.: Todas, um canal, uma aba do CRM). O ativo fica com a
// pílula verde da marca; o número é o de não lidas/pendentes que o Chatwoot já calcula.
import Icon from 'next/icon/Icon.vue';

defineProps({
  item: { type: Object, required: true },
  active: { type: Boolean, default: false },
  count: { type: Number, default: 0 },
  dense: { type: Boolean, default: false },
});

const emit = defineEmits(['navigate']);
</script>

<template>
  <li class="min-w-0 list-none">
    <RouterLink
      :to="item.to"
      :title="item.label"
      class="outsider-nav-leaf group flex items-center gap-2.5 min-w-0 rounded-lg px-2.5 text-[13px] transition-colors duration-100"
      :class="[
        dense ? 'h-8' : 'h-9',
        active
          ? 'bg-n-brand text-white font-medium shadow-sm active'
          : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12',
      ]"
      @click="emit('navigate')"
    >
      <span
        v-if="item.icon"
        class="grid place-content-center size-4 shrink-0 [&>*]:size-4"
        :class="active ? 'text-white' : 'text-n-slate-10 group-hover:text-n-slate-11'"
      >
        <Icon :icon="item.icon" class="size-4" />
      </span>
      <span v-else class="grid place-content-center size-4 shrink-0">
        <span
          class="rounded-full size-1.5"
          :class="active ? 'bg-white' : 'bg-n-slate-7'"
        />
      </span>
      <span class="flex-1 min-w-0 truncate">{{ item.label }}</span>
      <span
        v-if="count"
        class="outsider-nav-badge shrink-0"
        :class="{ 'outsider-nav-badge--on-brand': active }"
      >
        {{ count > 99 ? '99+' : count }}
      </span>
    </RouterLink>
  </li>
</template>
