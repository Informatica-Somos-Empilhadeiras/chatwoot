// OUTSIDER: o acesso de quem está logado (perfis de acesso, Outsider::Access::Resolver): o menu do computador e a
// barra do celular escondem o que o perfil não abre, as rotas voltam para a tela inicial do perfil (técnico: o
// telefone) e o telefone some com "Telefone" desligado. Busca de novo quando o administrador muda os perfis (aviso
// ao vivo 'access') e ao voltar para a aba.
import { reactive } from 'vue';
import AccessAPI from 'dashboard/api/outsider/access';
import { rank, screenForPath } from './catalog';

export const accessState = reactive({
  loaded: false,
  accountId: null,
  kind: 'agent',
  home: 'conversations',
  screens: {},
  locked: [],
  profile: null,
  catalog: [],
});

let loading = null;

export const loadAccess = async (accountId, { force = false } = {}) => {
  if (!accountId) return accessState;
  if (!force && accessState.loaded && accessState.accountId === accountId)
    return accessState;
  if (loading && !force) return loading;
  loading = AccessAPI.me()
    .then(({ data }) => {
      Object.assign(accessState, {
        loaded: true,
        accountId,
        kind: data.kind,
        home: data.home,
        screens: data.screens || {},
        locked: data.locked || [],
        profile: data.profile,
        catalog: data.catalog || [],
      });
      return accessState;
    })
    .catch(() => {
      // sem resposta: fica como estava (sem esconder nada a mais); a API continua conferindo
      return accessState;
    })
    .finally(() => {
      loading = null;
    });
  return loading;
};

export const levelOf = screen =>
  accessState.loaded ? accessState.screens[screen] || 'none' : 'use';

export const allows = (screen, atLeast = 'view') =>
  rank(levelOf(screen)) >= rank(atLeast);

// rota (caminho) que o perfil abre; o que não é de nenhuma tela do perfil passa
export const canOpenPath = path => {
  const screen = screenForPath(path);
  if (!screen) return true;
  return allows(screen, screen === 'phone' ? 'use' : 'view');
};

export const isTechnician = () =>
  accessState.loaded && accessState.kind === 'technician';
