// OUTSIDER: o "modelo" da navegação, usado pelo menu lateral do computador (desktop/DesktopNav.vue)
// e pela barra de baixo do celular (responsive/MobileTabbar.vue).
//
// A fonte dos itens é sempre o menuItems do Sidebar.vue do Chatwoot. Aqui ele vira uma lista de
// módulos ({ name, label, icon, to, groups }) já filtrada pelas permissões da pessoa. Assim, um item
// novo que o Chatwoot criar numa atualização (ou um módulo nosso que se registra no menuItems)
// aparece sozinho nos dois menus, sem mexer neles.
import { h, isVNode } from 'vue';

export const renderIcon = icon => {
  if (!icon) return null;
  if (typeof icon === 'function' || isVNode(icon)) return icon;
  return h('span', { class: icon });
};

export const makeAllowed = isAllowed => to => {
  try {
    return !!to && isAllowed(to);
  } catch {
    return false;
  }
};

// item do menu -> { name, label, icon, to, groups: [{ name, label, icon, items }] } ou null
// - item sem filhos: um destino só (to)
// - filhos soltos viram o primeiro grupo (sem título)
// - filhos com filhos (Canais, Pastas, Times, Etiquetas...) viram grupos com título
export const toModule = (item, allowed) => {
  if (!item.children) {
    return allowed(item.to)
      ? {
          name: item.name,
          label: item.label,
          icon: item.icon,
          to: item.to,
          activeOn: item.activeOn || [],
          getterKeys: item.getterKeys,
          navSection: item.navSection,
          groups: [],
        }
      : null;
  }
  const loose = [];
  const groups = [];
  item.children.forEach(child => {
    if (child.children) {
      const items = child.children.filter(sub => allowed(sub.to));
      if (items.length)
        groups.push({
          name: child.name,
          label: child.label,
          icon: child.icon,
          items,
        });
    } else if (allowed(child.to)) {
      loose.push(child);
    }
  });
  if (loose.length)
    groups.unshift({ name: `${item.name}-main`, label: '', items: loose });
  if (!groups.length) return null;
  return {
    name: item.name,
    label: item.label,
    icon: item.icon,
    to: null,
    navSection: item.navSection,
    groups,
  };
};

export const toModules = (menuItems, allowed) =>
  (menuItems || []).map(item => toModule(item, allowed)).filter(Boolean);

export const itemsOf = module =>
  module.to ? [module] : module.groups.flatMap(g => g.items);

export const countOf = (item, getters) => {
  if (item.getterKeys?.count) return getters[item.getterKeys.count] || 0;
  return Number(item.badgeCount) || 0;
};

// a maior contagem entre as opções: elas se sobrepõem (as não lidas de "Todas" já incluem as de
// cada canal, pasta ou etiqueta), então somar contaria a mesma conversa várias vezes
export const moduleCount = (module, getters) =>
  itemsOf(module).reduce(
    (biggest, item) => Math.max(biggest, countOf(item, getters)),
    0
  );

const paramsMatch = (item, route) =>
  Object.keys(item.to?.params || {}).every(
    key => String(item.to.params[key]) === String(route.params[key])
  );

// O destino ativo, um só para a tela inteira, com a mesma ordem de preferência do Chatwoot
// (SidebarGroup.vue): caminho igual, depois activeOn (desempatando pelos parâmetros, ex.: a aba do
// CRM), depois o caminho mais longo que começa a rota atual (ex.: conversa aberta dentro do canal).
export const findActiveItem = (modules, route, resolvePath) => {
  const items = modules.flatMap(itemsOf).filter(item => item.to);
  const paths = new Map(items.map(item => [item, resolvePath(item.to)]));

  const samePath = items.find(item => paths.get(item) === route.path);
  if (samePath) return samePath;

  const byActiveOn = items.filter(item => item.activeOn?.includes(route.name));
  if (byActiveOn.length)
    return byActiveOn.find(item => paramsMatch(item, route)) || byActiveOn[0];

  let best = null;
  items.forEach(item => {
    const path = paths.get(item);
    if (!path || path === '/' || !route.path.startsWith(`${path}/`)) return;
    if (!best || path.length > paths.get(best).length) best = item;
  });
  return best;
};

export const moduleOfItem = (modules, item) =>
  item ? modules.find(module => itemsOf(module).includes(item)) : null;
