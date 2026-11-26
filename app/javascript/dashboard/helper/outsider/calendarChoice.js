// OUTSIDER: agendas compartilhadas. Quais agendas a pessoa quer ver na Agenda dos Aplicativos (visible) e em qual ela
// marca os eventos (target, também a do Agendar OS), por empresa (google | microsoft). Fica nas preferências da pessoa
// no Chatwoot (ui_settings), então vale em qualquer computador. 'primary' = a agenda principal dela.

const keyOf = provider => `outsider_calendars_${provider}`;

export const PRIMARY = 'primary';

export const savedChoice = (uiSettings, provider) => {
  const saved = (uiSettings && uiSettings[keyOf(provider)]) || {};
  return {
    visible: Array.isArray(saved.visible) ? saved.visible : [PRIMARY],
    target: saved.target || PRIMARY,
  };
};

export const choicePatch = (uiSettings, provider, patch) => ({
  [keyOf(provider)]: { ...savedChoice(uiSettings, provider), ...patch },
});

// a agenda onde marcar: a lembrada, se ainda existe e dá para editar; senão a principal
export const targetOf = (calendars, wanted) => {
  const editable = (calendars || []).filter(item => item.can_edit);
  return (
    (editable.find(item => item.id === wanted) || editable[0])?.id || PRIMARY
  );
};

// as agendas a mostrar que ainda existem (a principal quando nenhuma)
export const visibleOf = (calendars, wanted) => {
  const ids = (calendars || []).map(item => item.id);
  const list = (wanted || []).filter(id => ids.includes(id));
  return list.length ? list : [PRIMARY];
};

// cor de cada agenda na tela: as classes c0..c4 da Agenda, pela posição na lista
export const colorClassOf = (calendars, id) => {
  const index = (calendars || []).findIndex(item => item.id === id);
  return `c${Math.max(index, 0) % 5}`;
};
