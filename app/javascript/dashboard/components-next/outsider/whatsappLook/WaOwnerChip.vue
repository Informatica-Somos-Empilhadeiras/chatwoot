<script setup>
// OUTSIDER: quem está com a conversa (agente, "Você", bot ou "Sem responsável"), usado no cartão
// da lista de conversas nas duas larguras.
import Avatar from 'next/avatar/Avatar.vue';

defineProps({
  owner: { type: Object, required: true },
});
</script>

<template>
  <span
    class="inline-flex items-center gap-1 py-px ltr:pl-px ltr:pr-1.5 rtl:pr-px rtl:pl-1.5 text-[11px] font-medium leading-4 rounded-full shrink-0 min-w-0"
    :class="{
      'bg-n-alpha-2 text-n-slate-11': owner.kind === 'agent',
      'bg-n-teal-3 text-n-teal-11': owner.kind === 'me',
      'bg-n-iris-3 text-n-iris-11': owner.kind === 'bot',
      'bg-n-amber-3 text-n-amber-11 !pl-1.5': owner.kind === 'none',
    }"
    data-owner-chip
  >
    <Avatar
      v-if="owner.kind === 'agent' || owner.kind === 'me'"
      :name="owner.name"
      :src="owner.thumbnail"
      :size="14"
      rounded-full
    />
    <span v-else-if="owner.kind === 'bot'" class="i-lucide-bot size-3" />
    <span v-else class="i-lucide-user-round-x size-3" />
    <span class="truncate">{{ owner.name }}</span>
  </span>
</template>
