// OUTSIDER: rotas que o perfil de acesso não abre voltam para a tela inicial do perfil (técnico: o telefone). Fica em
// OutsiderGlobal (todas as telas do painel). Também confere a rota atual quando o acesso chega ou muda.
import { watch, onBeforeUnmount } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useEventListener } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { onCrmAccessChange } from '../crm/live';
import { accessState, canOpenPath, loadAccess } from './accessStore';
import { HOME_ROUTES } from './catalog';

export const homeLocation = accountId => ({
  name: HOME_ROUTES[accessState.home] || 'home',
  params: { accountId },
});

export const useAccessGuard = () => {
  const router = useRouter();
  const route = useRoute();
  const accountId = useMapGetter('getCurrentAccountId');

  const redirectIfBlocked = () => {
    if (!accessState.loaded || !accountId.value) return;
    if (canOpenPath(route.fullPath)) return;
    const home = homeLocation(accountId.value);
    if (router.resolve(home).fullPath === route.fullPath) return;
    router.replace(home);
  };

  const removeGuard = router.beforeEach(to => {
    if (!accessState.loaded || !to.params?.accountId) return true;
    if (canOpenPath(to.fullPath)) return true;
    const home = homeLocation(to.params.accountId);
    // a própria tela inicial nunca é bloqueada (evita voltar para ela em círculo)
    if (router.resolve(home).fullPath === to.fullPath) return true;
    return home;
  });
  onBeforeUnmount(removeGuard);

  watch(
    accountId,
    async id => {
      if (!id) return;
      await loadAccess(id);
      redirectIfBlocked();
    },
    { immediate: true }
  );

  // o administrador mudou os perfis ou as pessoas
  const stopLive = onCrmAccessChange(() => {
    loadAccess(accountId.value, { force: true }).then(redirectIfBlocked);
  });
  onBeforeUnmount(stopLive);

  useEventListener(document, 'visibilitychange', () => {
    if (document.visibilityState !== 'visible' || !accountId.value) return;
    loadAccess(accountId.value, { force: true }).then(redirectIfBlocked);
  });

  return { accessState };
};
