<script setup>
// OUTSIDER: setinha de opções no canto da bolha, como no WhatsApp. Abre o mesmo menu do clique
// direito; o topo da bolha escurece um pouco enquanto o mouse está na setinha.
// O clique direito ignora fotos, links e texto selecionado (para o menu do navegador); a setinha
// não: limpa a seleção e abre o menu logo abaixo dela, com qualquer tipo de bolha.
import { useI18n } from 'vue-i18n';

defineProps({
  showMenu: { type: Boolean, default: false },
});
const emit = defineEmits(['openMenu']);

const { t } = useI18n();

const openMenu = event => {
  window.getSelection()?.removeAllRanges();
  const rect = event.currentTarget.getBoundingClientRect();
  emit('openMenu', {
    type: 'click',
    target: event.currentTarget,
    pageX: rect.left,
    pageY: rect.bottom + 4,
    preventDefault: () => {},
  });
};
</script>

<template>
  <div class="relative flex max-w-full group isolate">
    <slot />
    <button
      v-if="showMenu"
      type="button"
      class="absolute z-20 items-center justify-center hidden transition-all bg-white border rounded-full shadow-sm cursor-pointer peer group-hover:flex top-1 ltr:right-1.5 rtl:left-1.5 size-7 dark:bg-[#151718] border-black/5 dark:border-white/10 text-n-slate-11 hover:text-n-slate-12 hover:bg-slate-100 dark:hover:bg-slate-800"
      :title="t('OUTSIDER_WHATSAPP.MESSAGE_MENU')"
      @mousedown.prevent
      @click.prevent.stop="openMenu"
    >
      <span class="i-lucide-chevron-down size-4" />
    </button>
    <div
      v-if="showMenu"
      class="absolute inset-x-0 top-0 z-10 hidden h-10 transition-all rounded-t-lg pointer-events-none peer-hover:block bg-gradient-to-b from-black/20 to-transparent"
    />
  </div>
</template>
