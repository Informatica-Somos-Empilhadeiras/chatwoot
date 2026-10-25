// OUTSIDER: item Telefonia no menu lateral (Entrega 23), com as seções como subitens, igual ao CRM. Some
// sem acesso ao CRM e, para quem não é administrador, com a telefonia desligada.
import { crmState } from '../crm/crmStore';
import { VOICE_ROUTE, voiceSections } from './sections';

export const voiceSidebarItems = (t, accountScopedRoute) => {
  const sections = voiceSections(crmState.access);
  if (!sections.length) return [];
  return [
    {
      name: 'OutsiderVoice',
      label: t('OUTSIDER_VOICE.SECTION.TITLE'),
      icon: 'i-lucide-phone',
      children: sections.map(section => ({
        name: `OutsiderVoice-${section.key}`,
        label: t(section.label),
        icon: section.icon,
        activeOn: [VOICE_ROUTE],
        to: accountScopedRoute(VOICE_ROUTE, { tab: section.key }),
      })),
    },
  ];
};
