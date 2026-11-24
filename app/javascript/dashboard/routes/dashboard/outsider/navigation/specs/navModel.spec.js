import { toModules, moduleCount, itemsOf } from '../navModel';
import { groupBySection } from '../sections';
import { modulePill, shortCount } from '../desktop/navCounts';

const allowed = () => true;
const menu = [
  {
    name: 'Conversation',
    label: 'Conversas',
    children: [
      { name: 'All', label: 'Todas', to: '/all', badgeCount: 12 },
      { name: 'Mentions', label: 'Menções', to: '/mentions', badgeCount: 2 },
      {
        name: 'Channels',
        label: 'Canais',
        children: [
          { name: 'wa-1', label: 'WhatsApp', to: '/inbox/1', badgeCount: 6 },
        ],
      },
    ],
  },
  { name: 'NovoModulo', label: 'Novo', to: '/novo' },
  { name: 'Reports', label: 'Relatórios', to: '/reports' },
];

describe('navModel', () => {
  it('turns the menu into modules with loose items first and titled groups', () => {
    const [conversation] = toModules(menu, allowed);
    expect(conversation.groups.map(g => g.name)).toEqual([
      'Conversation-main',
      'Channels',
    ]);
    expect(itemsOf(conversation)).toHaveLength(3);
  });

  it('uses the biggest count of the module, since the options overlap', () => {
    const [conversation] = toModules(menu, allowed);
    expect(moduleCount(conversation, {})).toBe(12);
  });

  it('puts unknown modules in the "Mais" section', () => {
    const sections = groupBySection(toModules(menu, allowed));
    expect(sections.map(s => s.key)).toEqual(['atendimento', 'gestao', 'mais']);
    expect(sections[2].modules[0].name).toBe('NovoModulo');
  });
});

describe('navCounts', () => {
  const t = (key, named) => `${key}:${named.count}`;

  it('adds the text of the module to the count', () => {
    expect(modulePill('Conversation', 12, t)).toEqual({
      text: 'OUTSIDER_NAV.COUNT.UNREAD:12',
      soft: false,
    });
    expect(modulePill('OutsiderCrm', 2, t).soft).toBe(true);
    expect(modulePill('Reports', 3, t).text).toBe('3');
  });

  it('caps long counts', () => {
    expect(shortCount(150)).toBe('99+');
  });
});
