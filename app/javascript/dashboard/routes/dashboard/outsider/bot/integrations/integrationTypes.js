// OUTSIDER: os blocos de integração do fluxograma do bot (mesmos tipos e saídas do
// Outsider::Bot::IntegrationGraph no servidor): o que cada um tem de padrão, as saídas, o resumo do
// cartão e os avisos. Entram no nodeTypes.js.
import { usedVariables } from './template';

export const INTEGRATION_TYPES = [
  'api',
  'db_query',
  'sheet',
  'doc_search',
  'doc_send',
  'decision',
];

export const WRITE_METHODS = ['POST', 'PUT', 'PATCH', 'DELETE'];
export const DECISION_OPERATORS = [
  'equals',
  'not_equals',
  'contains',
  'not_contains',
  'starts_with',
  'ends_with',
  'greater',
  'less',
  'empty',
  'not_empty',
];
export const NO_VALUE_OPERATORS = ['empty', 'not_empty'];
export const SHEET_OPERATORS = [
  'equals',
  'contains',
  'starts_with',
  'ends_with',
];
const MAX_RULES = 10;

let counter = 0;
export const ruleId = () => {
  counter += 1;
  return `rule_${Date.now().toString(36)}${counter.toString(36)}${Math.random()
    .toString(36)
    .slice(2, 5)}`;
};

export const INTEGRATION_NODE_TYPES = {
  api: {
    icon: 'i-lucide-plug-zap',
    color: 'bg-n-violet-9',
    soft: 'bg-n-violet-3 text-n-violet-11',
    defaults: () => ({
      connection_id: null,
      method: 'GET',
      path: '',
      query: [],
      headers: [],
      body_type: 'none',
      body: '',
      graphql_query: '',
      form: [],
      variable: 'resultado',
      mappings: [],
      cache_seconds: 0,
      timeout_seconds: 0,
    }),
  },
  db_query: {
    icon: 'i-lucide-database',
    color: 'bg-n-violet-10',
    soft: 'bg-n-violet-3 text-n-violet-11',
    defaults: () => ({
      connection_id: null,
      sql: '',
      mode: 'first',
      limit: 20,
      variable: 'registro',
    }),
  },
  sheet: {
    icon: 'i-lucide-sheet',
    color: 'bg-n-teal-10',
    soft: 'bg-n-teal-3 text-n-teal-11',
    defaults: () => ({
      dataset_id: null,
      column: '',
      operator: 'equals',
      value: '',
      variable: 'linha',
    }),
  },
  doc_search: {
    icon: 'i-lucide-file-search',
    color: 'bg-n-blue-10',
    soft: 'bg-n-blue-3 text-n-blue-11',
    defaults: () => ({
      connection_id: null,
      folder: '/',
      query: '',
      extensions: [],
      limit: 5,
      pick: 'ask',
      text: '',
      button_label: 'Ver documentos',
      variable: 'documento',
      max_attempts: 2,
    }),
  },
  doc_send: {
    icon: 'i-lucide-file-up',
    color: 'bg-n-blue-10',
    soft: 'bg-n-blue-3 text-n-blue-11',
    defaults: () => ({
      source: 'documento',
      mode: 'file',
      caption: '',
      link_text: '',
      link_days: 7,
    }),
  },
  decision: {
    icon: 'i-lucide-split',
    color: 'bg-n-amber-10',
    soft: 'bg-n-amber-3 text-n-amber-11',
    defaults: () => ({
      subject: '',
      rules: [{ id: ruleId(), label: '', operator: 'equals', value: '' }],
    }),
  },
};

export const isIntegration = type => INTEGRATION_TYPES.includes(type);
export const isGraphql = data => data?.body_type === 'graphql';
export const graphqlWrites = query =>
  /(^|\})\s*(mutation|subscription)\b/.test(
    String(query || '').replace(/#[^\n]*/g, '')
  );
export const apiWrites = data =>
  isGraphql(data)
    ? graphqlWrites(data.graphql_query)
    : WRITE_METHODS.includes(data?.method);

const operatorShort = (operator, t) =>
  t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.OPERATORS_SHORT.${operator}`);

export const ruleLabel = (rule, t) => {
  if (rule.label) return rule.label;
  const value = NO_VALUE_OPERATORS.includes(rule.operator)
    ? ''
    : ` ${rule.value || '—'}`;
  return `${operatorShort(rule.operator, t)}${value}`;
};

export const integrationPorts = (node, t) => {
  const data = node.data || {};
  const port = (id, muted = false) => ({
    id,
    label: t(`OUTSIDER_TOOLS.BOT.PORTS.${id}`),
    muted,
  });
  switch (node.type) {
    case 'api':
    case 'doc_send':
      return [port('ok'), port('error', true)];
    case 'sheet':
      return [port('found'), port('not_found', true)];
    case 'doc_search':
    case 'db_query':
      return [port('found'), port('not_found', true), port('error', true)];
    case 'decision':
      return [
        ...(data.rules || []).slice(0, MAX_RULES).map(rule => ({
          id: rule.id,
          label: ruleLabel(rule, t),
        })),
        {
          ...port('default', true),
          label: t('OUTSIDER_TOOLS.BOT.PORTS.otherwise'),
        },
      ];
    default:
      return [];
  }
};

const findConnection = (ctx, id) =>
  (ctx?.connections || []).find(item => item.id === Number(id));
const findDataset = (ctx, id) =>
  (ctx?.datasets || []).find(item => item.id === Number(id));

const shortSql = sql =>
  String(sql || '')
    .replace(/\s+/g, ' ')
    .trim();

export const integrationSummary = (node, t, ctx) => {
  const d = node.data || {};
  const empty = t('OUTSIDER_TOOLS.BOT.SUMMARY.EMPTY');
  switch (node.type) {
    case 'api': {
      const name = findConnection(ctx, d.connection_id)?.name;
      const call = isGraphql(d)
        ? `GraphQL ${d.path || ''}`.trim()
        : `${d.method} ${d.path || '/'}`;
      return name ? `${name}\n${call}` : empty;
    }
    case 'db_query': {
      const name = findConnection(ctx, d.connection_id)?.name;
      return name ? `${name}\n${shortSql(d.sql) || '—'}` : empty;
    }
    case 'sheet': {
      const dataset = findDataset(ctx, d.dataset_id);
      if (!dataset) return empty;
      const column =
        dataset.columns?.find(item => item.key === d.column)?.label ||
        d.column ||
        '—';
      return `${dataset.name}\n${column} ${operatorShort(d.operator, t)} ${d.value || '—'}`;
    }
    case 'doc_search': {
      const name = findConnection(ctx, d.connection_id)?.name;
      if (!name) return empty;
      return `${name} · ${d.folder || '/'}\n${d.query || t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SUMMARY.LATEST')}`;
    }
    case 'doc_send':
      return t(
        d.mode === 'link'
          ? 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.SUMMARY.SEND_LINK'
          : 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.SUMMARY.SEND_FILE',
        { source: `{{${d.source || 'documento'}}}`, days: d.link_days }
      );
    case 'decision':
      return (
        d.subject || t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SUMMARY.NO_SUBJECT')
      );
    default:
      return empty;
  }
};

export const integrationBadge = (node, t) => {
  const d = node.data || {};
  switch (node.type) {
    case 'api':
    case 'db_query':
    case 'sheet':
    case 'doc_search':
      return d.variable ? `{{${d.variable}}}` : '';
    case 'doc_send':
      return t(
        `OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND_MODES.${d.mode || 'file'}`
      );
    case 'decision':
      return t(
        'OUTSIDER_TOOLS.BOT.INTEGRATIONS.SUMMARY.RULES',
        { count: (d.rules || []).length },
        (d.rules || []).length
      );
    default:
      return '';
  }
};

export const integrationWarnings = (node, t, ctx) => {
  const d = node.data || {};
  const list = [];
  const w = key => t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.WARNINGS.${key}`);
  const loaded = !!ctx?.loaded;
  const checkConnection = kind => {
    if (!d.connection_id) {
      list.push(w('NO_CONNECTION'));
      return null;
    }
    const connection = findConnection(ctx, d.connection_id);
    if (loaded && (!connection || connection.kind !== kind)) {
      list.push(w('CONNECTION_GONE'));
    }
    return connection;
  };
  switch (node.type) {
    case 'api': {
      const connection = checkConnection('http');
      if (connection && !connection.allow_write && apiWrites(d)) {
        list.push(w('READ_ONLY'));
      }
      if (isGraphql(d) && !String(d.graphql_query || '').trim()) {
        list.push(w('NO_GRAPHQL'));
      }
      break;
    }
    case 'db_query':
      checkConnection('postgres');
      if (!String(d.sql || '').trim()) list.push(w('NO_SQL'));
      break;
    case 'sheet': {
      if (!d.dataset_id) list.push(w('NO_DATASET'));
      else if (loaded && !findDataset(ctx, d.dataset_id)) {
        list.push(w('DATASET_GONE'));
      }
      if (!d.column) list.push(w('NO_COLUMN'));
      if (!String(d.value || '').trim()) list.push(w('NO_VALUE'));
      break;
    }
    case 'doc_search':
      checkConnection('nextcloud');
      break;
    case 'doc_send':
      if (
        d.mode === 'link' &&
        d.link_text &&
        !d.link_text.includes('{{link}}')
      ) {
        list.push(w('NO_LINK'));
      }
      break;
    case 'decision':
      if (!String(d.subject || '').trim()) list.push(w('NO_SUBJECT'));
      if (!(d.rules || []).length) list.push(w('NO_RULES'));
      break;
    default:
      break;
  }
  return list;
};

// variáveis que os blocos do fluxo guardam, para os botões de inserir nos textos
export const flowVariables = (nodes, ctx) => {
  const list = [];
  const add = value => {
    if (!list.includes(value)) list.push(value);
  };
  nodes.forEach(node => {
    const d = node.data || {};
    switch (node.type) {
      case 'question':
        if (d.variable) add(`{{${d.variable.toLowerCase()}}}`);
        break;
      case 'api':
        (d.mappings || []).forEach(item => add(`{{${item.variable}}}`));
        if (d.variable) add(`{{${d.variable}}}`);
        break;
      case 'sheet': {
        const dataset = findDataset(ctx, d.dataset_id);
        (dataset?.columns || [])
          .slice(0, 8)
          .forEach(column => add(`{{${d.variable}.${column.key}}}`));
        break;
      }
      case 'doc_search':
        add(`{{${d.variable}.nome}}`);
        break;
      case 'db_query':
        if (d.variable) add(`{{${d.variable}}}`);
        break;
      default:
        break;
    }
  });
  if (nodes.some(node => isIntegration(node.type))) add('{{erro}}');
  return list;
};

// variáveis de documento guardadas por Buscar documento (para o Enviar documento)
export const documentVariables = nodes => [
  ...new Set(
    nodes
      .filter(node => node.type === 'doc_search')
      .map(node => node.data?.variable || 'documento')
  ),
];

export const blockVariables = node => usedVariables(node.data || {});

// texto do erro de um bloco (variável {{erro}} e Registro) para a tela
export const errorText = (code, t, te) => {
  if (!code) return '';
  const http = String(code).match(/^http_(\d+)$/);
  if (http) {
    return t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.ERRORS.http', {
      status: http[1],
    });
  }
  const key = `OUTSIDER_TOOLS.BOT.INTEGRATIONS.ERRORS.${code}`;
  return te(key)
    ? t(key)
    : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.ERRORS.unknown', { code });
};

// valor de teste digitado: JSON vira objeto (para {{linha.modelo}}), o resto fica texto
export const parseTestValue = text => {
  const value = String(text ?? '');
  if (/^\s*[[{]/.test(value)) {
    try {
      return JSON.parse(value);
    } catch {
      return value;
    }
  }
  return value;
};

export const showValue = value => {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
};

export const PORT_TONES = {
  ok: 'bg-n-teal-3 text-n-teal-11',
  found: 'bg-n-teal-3 text-n-teal-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
  not_found: 'bg-n-amber-3 text-n-amber-11',
  default: 'bg-n-amber-3 text-n-amber-11',
};
