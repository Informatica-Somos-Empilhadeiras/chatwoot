// OUTSIDER: os blocos do fluxograma do bot (mesmos tipos e saídas do Outsider::Bot::Graph no servidor).
// O cartão tem medidas fixas para as setas saírem sempre do lugar certo, sem medir a tela.
export const NODE_WIDTH = 260;
export const HEADER_HEIGHT = 40;
export const BODY_HEIGHT = 66;
export const PORT_HEIGHT = 28;
export const MAX_OPTIONS = 10;
export const MAX_BUTTONS = 3;

let counter = 0;
export const newId = prefix => {
  counter += 1;
  const random = Math.random().toString(36).slice(2, 5);
  return `${prefix}_${Date.now().toString(36)}${counter.toString(36)}${random}`;
};

export const DEFAULT_HOURS = Object.fromEntries(
  [0, 1, 2, 3, 4, 5, 6].map(day => [
    String(day),
    { enabled: day >= 1 && day <= 5, start: '08:00', end: '18:00' },
  ])
);

export const NODE_TYPES = {
  start: {
    icon: 'i-lucide-play',
    color: 'bg-n-teal-9',
    soft: 'bg-n-teal-3 text-n-teal-11',
    palette: false,
    defaults: () => ({
      trigger: 'unassigned_message',
      keywords: [],
      cooldown_hours: 12,
      timeout_minutes: 60,
      set_pending: true,
      only_unassigned: true,
    }),
  },
  message: {
    icon: 'i-lucide-message-square-text',
    color: 'bg-n-blue-9',
    soft: 'bg-n-blue-3 text-n-blue-11',
    defaults: () => ({ text: '', delay_seconds: 1 }),
  },
  menu: {
    icon: 'i-lucide-list',
    color: 'bg-n-iris-9',
    soft: 'bg-n-iris-3 text-n-iris-11',
    defaults: () => ({
      text: '',
      title: '',
      footer: '',
      style: 'list',
      button_label: 'Ver opções',
      options: [
        { id: newId('opt'), label: 'Sim', description: '' },
        { id: newId('opt'), label: 'Não', description: '' },
      ],
      invalid_text: '',
      max_attempts: 2,
    }),
  },
  question: {
    icon: 'i-lucide-message-circle-question',
    color: 'bg-n-amber-9',
    soft: 'bg-n-amber-3 text-n-amber-11',
    defaults: () => ({
      text: '',
      variable: 'resposta',
      contact_field: '',
      routes: [],
    }),
  },
  condition: {
    icon: 'i-lucide-clock',
    color: 'bg-n-slate-9',
    soft: 'bg-n-slate-3 text-n-slate-11',
    defaults: () => ({
      hours: JSON.parse(JSON.stringify(DEFAULT_HOURS)),
      timezone: 'America/Sao_Paulo',
    }),
  },
  action: {
    icon: 'i-lucide-zap',
    color: 'bg-n-ruby-9',
    soft: 'bg-n-ruby-3 text-n-ruby-11',
    defaults: () => ({
      team_id: null,
      assignee_id: null,
      labels: [],
      priority: null,
      note: '',
    }),
  },
  handoff: {
    icon: 'i-lucide-headset',
    color: 'bg-n-brand',
    soft: 'bg-n-brand/10 text-n-brand',
    defaults: () => ({ text: '', team_id: null, assignee_id: null }),
  },
  end: {
    icon: 'i-lucide-flag',
    color: 'bg-n-slate-11',
    soft: 'bg-n-slate-4 text-n-slate-12',
    defaults: () => ({ text: '', resolve: false }),
  },
};

export const PALETTE = [
  'message',
  'menu',
  'question',
  'condition',
  'action',
  'handoff',
  'end',
];

// saídas do bloco: [{ id, label, kind }] (kind diz como escrever o rótulo)
export const portsOf = (node, t) => {
  const data = node.data || {};
  switch (node.type) {
    case 'start':
    case 'message':
    case 'action':
      return [{ id: 'next', label: t('OUTSIDER_TOOLS.BOT.PORTS.next') }];
    case 'menu':
      return [
        ...(data.options || []).map((option, index) => ({
          id: option.id,
          label: `${index + 1}. ${option.label || '—'}`,
        })),
        {
          id: 'invalid',
          label: t('OUTSIDER_TOOLS.BOT.PORTS.invalid'),
          muted: true,
        },
      ];
    case 'question':
      return [
        ...(data.routes || []).map(route => ({
          id: route.id,
          label: route.label || (route.keywords || []).join(', ') || '—',
        })),
        {
          id: 'default',
          label: t('OUTSIDER_TOOLS.BOT.PORTS.default'),
          muted: true,
        },
      ];
    case 'condition':
      return [
        { id: 'inside', label: t('OUTSIDER_TOOLS.BOT.PORTS.inside') },
        {
          id: 'outside',
          label: t('OUTSIDER_TOOLS.BOT.PORTS.outside'),
          muted: true,
        },
      ];
    default:
      return [];
  }
};

export const nodeHeight = (node, t) =>
  HEADER_HEIGHT + BODY_HEIGHT + portsOf(node, t).length * PORT_HEIGHT + 8;

// pontos onde a seta sai (porta) e chega (entrada), no sistema do quadro
export const portPoint = (node, portId, t) => {
  const index = portsOf(node, t).findIndex(port => port.id === portId);
  return {
    x: node.x + NODE_WIDTH,
    y:
      node.y +
      HEADER_HEIGHT +
      BODY_HEIGHT +
      Math.max(index, 0) * PORT_HEIGHT +
      PORT_HEIGHT / 2,
  };
};

export const inputPoint = node => ({
  x: node.x,
  y: node.y + HEADER_HEIGHT / 2,
});

export const edgePath = (from, to) => {
  const dx = Math.max(Math.abs(to.x - from.x) / 2, 60);
  return `M ${from.x} ${from.y} C ${from.x + dx} ${from.y}, ${to.x - dx} ${to.y}, ${to.x} ${to.y}`;
};

export const makeNode = (type, x, y) => ({
  id: newId(type),
  type,
  x: Math.round(x),
  y: Math.round(y),
  data: NODE_TYPES[type].defaults(),
});

// os bots não aceitam tudo: cada aviso aparece no bloco e no painel da direita
export const warningsOf = (node, edges, t) => {
  const data = node.data || {};
  const warnings = [];
  const connected = portId =>
    edges.some(edge => edge.from === node.id && edge.port === portId);
  if (['message', 'menu', 'question', 'handoff', 'end'].includes(node.type)) {
    if (!String(data.text || '').trim() && node.type !== 'end') {
      warnings.push(t('OUTSIDER_TOOLS.BOT.WARNINGS.EMPTY_TEXT'));
    }
  }
  if (node.type === 'menu') {
    if (!(data.options || []).length) {
      warnings.push(t('OUTSIDER_TOOLS.BOT.WARNINGS.NO_OPTIONS'));
    }
    if (data.style === 'buttons' && (data.options || []).length > MAX_BUTTONS) {
      warnings.push(t('OUTSIDER_TOOLS.BOT.WARNINGS.TOO_MANY_BUTTONS'));
    }
    if (
      data.style === 'buttons' &&
      (data.options || []).some(option => (option.label || '').length > 20)
    ) {
      warnings.push(t('OUTSIDER_TOOLS.BOT.WARNINGS.BUTTON_TOO_LONG'));
    }
  }
  const ports = portsOf(node, t).filter(port => !port.muted);
  if (ports.length && ports.every(port => !connected(port.id))) {
    warnings.push(t('OUTSIDER_TOOLS.BOT.WARNINGS.NOT_CONNECTED'));
  }
  return warnings;
};

// variáveis que dá para usar nos textos
export const VARIABLES = [
  '{{contato.primeiro_nome}}',
  '{{contato.nome}}',
  '{{contato.telefone}}',
  '{{contato.email}}',
];
