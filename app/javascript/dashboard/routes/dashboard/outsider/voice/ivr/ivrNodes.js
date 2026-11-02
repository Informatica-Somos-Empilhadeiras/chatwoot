// OUTSIDER: os blocos da URA (Entrega 26), os mesmos tipos e saídas do Outsider::Voice::IvrGraph no servidor.
// Medidas, ids e setas iguais às do fluxograma do bot (../../bot/nodeTypes.js), para as duas telas terem o
// mesmo jeito.
import {
  NODE_WIDTH,
  HEADER_HEIGHT,
  BODY_HEIGHT,
  PORT_HEIGHT,
  DEFAULT_HOURS,
  newId,
} from '../../bot/nodeTypes';

export {
  NODE_WIDTH,
  HEADER_HEIGHT,
  BODY_HEIGHT,
  PORT_HEIGHT,
  edgePath,
  newId,
} from '../../bot/nodeTypes';

export const MAX_NODES = 150;
export const MAX_OPTIONS = 12;
// "#" encerra a digitação no telefone: não serve de opção
export const DIGITS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '*'];
export const TARGETS = ['default', 'owner', 'users', 'branch', 'number'];

const prompt = (text = '') => ({ text, audio_id: null });

export const NODE_TYPES = {
  start: {
    icon: 'i-lucide-phone-incoming',
    color: 'bg-n-teal-9',
    soft: 'bg-n-teal-3 text-n-teal-11',
    palette: false,
    defaults: () => ({ voice: 'nova' }),
  },
  say: {
    icon: 'i-lucide-volume-2',
    color: 'bg-n-blue-9',
    soft: 'bg-n-blue-3 text-n-blue-11',
    defaults: () => ({ prompt: prompt() }),
  },
  menu: {
    icon: 'i-lucide-grid-3x3',
    color: 'bg-n-iris-9',
    soft: 'bg-n-iris-3 text-n-iris-11',
    defaults: () => ({
      label: '',
      prompt: prompt(),
      invalid_prompt: prompt(),
      options: [
        { id: newId('opt'), digit: '1', label: '' },
        { id: newId('opt'), digit: '2', label: '' },
      ],
      timeout: 5,
      max_attempts: 3,
    }),
  },
  collect: {
    icon: 'i-lucide-binary',
    color: 'bg-n-amber-9',
    soft: 'bg-n-amber-3 text-n-amber-11',
    defaults: () => ({
      label: '',
      variable: 'digitos',
      prompt: prompt(),
      invalid_prompt: prompt(),
      min_digits: 1,
      max_digits: 11,
      timeout: 8,
      max_attempts: 2,
    }),
  },
  hours: {
    icon: 'i-lucide-clock',
    color: 'bg-n-slate-9',
    soft: 'bg-n-slate-3 text-n-slate-11',
    defaults: () => ({
      hours: JSON.parse(JSON.stringify(DEFAULT_HOURS)),
      timezone: 'America/Sao_Paulo',
    }),
  },
  caller: {
    icon: 'i-lucide-user-search',
    color: 'bg-n-violet-9',
    soft: 'bg-n-violet-3 text-n-violet-11',
    defaults: () => ({}),
  },
  transfer: {
    icon: 'i-lucide-phone-forwarded',
    color: 'bg-n-brand',
    soft: 'bg-n-brand/10 text-n-brand',
    defaults: () => ({
      prompt: prompt(),
      target: 'default',
      user_ids: [],
      branch_id: null,
      number: '',
      ring_seconds: 30,
    }),
  },
  voicemail: {
    icon: 'i-lucide-voicemail',
    color: 'bg-n-ruby-9',
    soft: 'bg-n-ruby-3 text-n-ruby-11',
    defaults: () => ({ prompt: prompt(), max_seconds: 120 }),
  },
  hangup: {
    icon: 'i-lucide-phone-off',
    color: 'bg-n-slate-11',
    soft: 'bg-n-slate-4 text-n-slate-12',
    defaults: () => ({ prompt: prompt() }),
  },
};

// lista de blocos do editor, em grupos
export const PALETTE = [
  { id: 'talk', types: ['say', 'menu', 'collect'] },
  { id: 'logic', types: ['hours', 'caller'] },
  { id: 'route', types: ['transfer', 'voicemail', 'hangup'] },
];

const PORT_KEYS = {
  start: ['next'],
  say: ['next'],
  voicemail: ['next'],
  collect: ['next', 'empty'],
  hours: ['inside', 'outside'],
  caller: ['deal', 'contact', 'unknown'],
  transfer: ['no_answer'],
};
// saídas "de escape" aparecem em itálico e não contam no aviso de bloco sem ligação
const MUTED = ['empty', 'invalid', 'outside', 'unknown', 'no_answer'];

// saídas do bloco: [{ id, label, muted }]
export const portsOf = (node, t) => {
  if (node.type === 'menu') {
    return [
      ...(node.data?.options || []).map(option => ({
        id: option.id,
        label: `${option.digit} · ${option.label || '—'}`,
      })),
      {
        id: 'invalid',
        label: t('OUTSIDER_VOICE.IVR.PORTS.invalid'),
        muted: true,
      },
    ];
  }
  return (PORT_KEYS[node.type] || []).map(id => ({
    id,
    label: t(`OUTSIDER_VOICE.IVR.PORTS.${id}`),
    muted: MUTED.includes(id),
  }));
};

export const nodeHeight = (node, t) =>
  HEADER_HEIGHT + BODY_HEIGHT + portsOf(node, t).length * PORT_HEIGHT + 8;

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

export const makeNode = (type, x, y) => ({
  id: newId(type),
  type,
  x: Math.round(x),
  y: Math.round(y),
  data: NODE_TYPES[type].defaults(),
});

const hasPrompt = value => !!(value?.text?.trim() || value?.audio_id);

// o que falta no bloco: cada aviso aparece no bloco e no painel da direita
export const warningsOf = (node, edges, t) => {
  const data = node.data || {};
  const warnings = [];
  const connected = portId =>
    edges.some(edge => edge.from === node.id && edge.port === portId);
  if (['say', 'menu', 'collect', 'voicemail'].includes(node.type)) {
    if (!hasPrompt(data.prompt)) {
      warnings.push(t('OUTSIDER_VOICE.IVR.WARNINGS.EMPTY_PROMPT'));
    }
  }
  if (node.type === 'menu' && !(data.options || []).length) {
    warnings.push(t('OUTSIDER_VOICE.IVR.WARNINGS.NO_OPTIONS'));
  }
  if (node.type === 'transfer') {
    if (data.target === 'users' && !(data.user_ids || []).length) {
      warnings.push(t('OUTSIDER_VOICE.IVR.WARNINGS.NO_USERS'));
    }
    if (data.target === 'branch' && !data.branch_id) {
      warnings.push(t('OUTSIDER_VOICE.IVR.WARNINGS.NO_BRANCH'));
    }
    if (
      data.target === 'number' &&
      String(data.number || '').replace(/\D/g, '').length < 10
    ) {
      warnings.push(t('OUTSIDER_VOICE.IVR.WARNINGS.NO_NUMBER'));
    }
  }
  const ports = portsOf(node, t).filter(port => !port.muted);
  if (ports.length && ports.every(port => !connected(port.id))) {
    warnings.push(t('OUTSIDER_VOICE.IVR.WARNINGS.NOT_CONNECTED'));
  }
  return warnings;
};

// um novo id para cada opção do menu copiado
export const copyNode = (node, x, y) => {
  const copy = JSON.parse(JSON.stringify(node));
  copy.id = newId(node.type);
  copy.x = x;
  copy.y = y;
  (copy.data.options || []).forEach(option => {
    option.id = newId('opt');
  });
  return copy;
};
