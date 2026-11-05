// OUTSIDER: como cada contagem aparece no menu lateral.
// - módulos com texto junto ao número ("12 não lidas", "8 novas", "2 tarefas"); os outros, só o número;
// - "soft" é a pílula cinza (pendências que não são mensagens), o resto usa o verde de destaque;
// - opções com pílula laranja (precisam de atenção).
const MODULE_PILLS = {
  Conversation: { key: 'UNREAD' },
  Inbox: { key: 'NEW' },
  OutsiderCrm: { key: 'TASKS', soft: true },
};

const WARN_ITEMS = ['Unattended'];

export const shortCount = count => (count > 99 ? '99+' : String(count));

export const modulePill = (moduleName, count, t) => {
  const pill = MODULE_PILLS[moduleName];
  const text = shortCount(count);
  return {
    text: pill
      ? t(`OUTSIDER_NAV.COUNT.${pill.key}`, { count: text }, count)
      : text,
    soft: !!pill?.soft,
  };
};

export const isWarnItem = item => WARN_ITEMS.includes(item?.name);
