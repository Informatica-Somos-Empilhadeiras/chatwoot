<script setup>
// OUTSIDER: no celular, o botão do menu fica no topo da lista de conversas, ao lado do título,
// em vez do botão redondo solto em cima da lista (que cobria as fotos das conversas).
// Ele aperta o mesmo botão do Chatwoot (MobileSidebarLauncher), que o responsive.css esconde
// enquanto este estiver na tela.
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const openMenu = () => {
  document.querySelector('#mobile-sidebar-launcher button')?.click();
};
</script>

<template>
  <button
    type="button"
    class="grid md:hidden place-content-center size-9 -ml-1 ltr:mr-1 rtl:ml-1 rounded-full shrink-0 text-n-slate-12 hover:bg-n-alpha-2 active:bg-n-alpha-3"
    :aria-label="t('OUTSIDER_RESPONSIVE.OPEN_MENU')"
    data-outsider-menu-button
    @click.stop="openMenu"
  >
    <span class="i-lucide-menu size-5" />
  </button>
</template>
