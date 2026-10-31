// OUTSIDER: as mesmas {{variáveis}} do servidor (Outsider::Bot::Template e Outsider::Bot::JsonPath), para o
// Testar do editor mostrar o texto como o cliente vai ver. Caminhos ({{pedido.itens.0.nome}},
// {{pedido.itens.nome}}, {{pedido.itens.quantidade}}) e filtros ({{cnpj | digitos}}, {{valor | moeda}}...).

export const PATTERN =
  /\{\{\s*([a-z0-9_.[\]*]+)\s*((?:\|\s*[a-z_]+(?::[^|}]*)?\s*)*)\}\}/gi;
const FILTER = /\|\s*([a-z_]+)(?::([^|}]*))?/gi;
const SEGMENTS = /\[(\d+|\*)\]|([^.[\]]+)/g;
const COUNT = ['quantidade', 'tamanho', 'length', 'count'];
const TIMEZONE = 'America/Sao_Paulo';

export const FILTERS = [
  'digitos',
  'maiusculas',
  'minusculas',
  'sem_acentos',
  'moeda',
  'data',
  'data_hora',
  'ultimos:4',
  'primeiros:20',
  'padrao:texto',
  'url',
];

const isObject = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

export const segments = path =>
  [...String(path || '').matchAll(SEGMENTS)].map(match => match[1] ?? match[2]);

const hashStep = (hash, key) => {
  if (Object.prototype.hasOwnProperty.call(hash, key)) return hash[key];
  const found = Object.keys(hash).find(
    item => item.toLowerCase() === String(key).toLowerCase()
  );
  return found === undefined ? undefined : hash[found];
};

const arrayStep = (list, key) => {
  if (key === '*') return list;
  if (COUNT.includes(String(key).toLowerCase())) return list.length;
  if (/^-?\d+$/.test(key)) {
    const index = Number(key);
    return index < 0 ? list[list.length + index] : list[index];
  }
  const values = list
    .filter(isObject)
    .map(item => hashStep(item, key))
    .filter(value => value !== undefined && value !== null);
  return values.length ? values : undefined;
};

export const dig = (data, path) =>
  segments(path).reduce((current, key) => {
    if (current === undefined || current === null) return undefined;
    if (Array.isArray(current)) return arrayStep(current, key);
    if (isObject(current)) return hashStep(current, key);
    return undefined;
  }, data);

export const toText = value => {
  if (value === undefined || value === null) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number') {
    return Number.isInteger(value) ? String(value) : String(value);
  }
  if (Array.isArray(value)) {
    return value.some(item => typeof item === 'object' && item !== null)
      ? JSON.stringify(value)
      : value.map(toText).join(', ');
  }
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

// número escrito do jeito brasileiro ou não: "1.234,56", "1234.56", "R$ 99,90"
export const parseNumber = value => {
  if (typeof value === 'number') return value;
  const text = String(value ?? '').replace(/[^\d,.-]/g, '');
  if (!/\d/.test(text)) return null;
  let normal = text;
  if (text.includes(',') && text.includes('.')) {
    normal =
      text.lastIndexOf(',') > text.lastIndexOf('.')
        ? text.replace(/\./g, '').replace(',', '.')
        : text.replace(/,/g, '');
  } else if (text.includes(',')) {
    normal =
      (text.match(/,/g) || []).length === 1
        ? text.replace(',', '.')
        : text.replace(/,/g, '');
  } else if (
    (text.match(/\./g) || []).length > 1 ||
    /^-?\d{1,3}(\.\d{3})+$/.test(text)
  ) {
    normal = text.replace(/\./g, '');
  }
  const number = Number(normal);
  return Number.isFinite(number) ? number : null;
};

const currency = value => {
  const number = parseNumber(value);
  if (number === null) return toText(value);
  return `R$ ${number.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
};

const formatDate = (value, withTime) => {
  const text = toText(value).trim();
  if (!text || /^\d{2}\/\d{2}\/\d{4}/.test(text)) return text;
  let date;
  if (/^\d{10}(\d{3})?$/.test(text))
    date = new Date(Number(text.slice(0, 10)) * 1000);
  else if (/^\d{4}-\d{2}-\d{2}$/.test(text))
    date = new Date(`${text}T12:00:00`);
  else date = new Date(text);
  if (Number.isNaN(date.getTime())) return text;
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: /^\d{4}-\d{2}-\d{2}$/.test(text) ? undefined : TIMEZONE,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    ...(withTime
      ? { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }
      : {}),
  })
    .format(date)
    .replace(',', '');
};

const urlEncode = text =>
  /^\.+$/.test(text) ? text.replace(/\./g, '%2E') : encodeURIComponent(text);

const clampCount = arg => Math.min(Math.max(parseInt(arg, 10) || 1, 1), 1000);

const applyFilter = (value, name, arg) => {
  switch (name) {
    case 'digitos':
      return toText(value).replace(/\D/g, '');
    case 'maiusculas':
      return toText(value).toUpperCase();
    case 'minusculas':
      return toText(value).toLowerCase();
    case 'sem_acentos':
      return toText(value).normalize('NFD').replace(/\p{M}/gu, '');
    case 'ultimos':
      return toText(value).slice(-clampCount(arg));
    case 'primeiros':
      return toText(value).slice(0, clampCount(arg));
    case 'padrao':
      return toText(value).trim() ? value : arg;
    case 'moeda':
      return currency(value);
    case 'data':
      return formatDate(value, false);
    case 'data_hora':
      return formatDate(value, true);
    case 'url':
      return urlEncode(toText(value));
    default:
      return value;
  }
};

export const valueOf = (variables, path, filters = '') =>
  [...String(filters || '').matchAll(FILTER)].reduce(
    (current, [, name, arg]) =>
      applyFilter(current, name.toLowerCase(), String(arg ?? '').trim()),
    dig(variables, path)
  );

// "{{nome}}" para mostrar na tela (o template do Vue não aceita "}}" dentro de {{ }})
export const braces = name => `{{${name}}}`;

export const renderTemplate = (text, variables) =>
  String(text || '').replace(PATTERN, (_, path, filters) =>
    toText(valueOf(variables, path, filters))
  );

// variáveis do contato e da conversa, como Outsider::Bot::Template#initialize
export const contactVariables = contact => {
  const name = contact?.name || '';
  const values = {
    nome: name,
    primeiro_nome: name.split(' ')[0] || '',
    telefone: contact?.phone_number || '',
    email: contact?.email || '',
    empresa: contact?.company || '',
    cidade: contact?.city || '',
    id: 0,
  };
  return {
    contato: values,
    conversa: { id: 0, numero: 0 },
    nome_contato: values.nome,
    primeiro_nome: values.primeiro_nome,
  };
};

const RESERVED_ROOTS = ['contato', 'conversa', 'nome_contato', 'primeiro_nome'];

// nomes das variáveis usadas nos campos de um bloco ({{cnpj | digitos}} -> cnpj), sem as do contato
export const usedVariables = value => {
  const names = new Set();
  const visit = item => {
    if (typeof item === 'string') {
      [...item.matchAll(PATTERN)].forEach(match => {
        const root = segments(match[1])[0];
        if (root && !RESERVED_ROOTS.includes(root.toLowerCase())) {
          names.add(root.toLowerCase());
        }
      });
    } else if (Array.isArray(item)) item.forEach(visit);
    else if (isObject(item)) Object.values(item).forEach(visit);
  };
  visit(value);
  return [...names];
};

// mesmo nome que o servidor guarda (Outsider::Bot::IntegrationGraph#variable_name)
const RESERVED_VARIABLES = ['contato', 'conversa', 'erro', 'link'];
export const variableName = (value, fallback) => {
  const name =
    String(value || '')
      .toLowerCase()
      .replace(/[^a-z0-9_]/g, '_')
      .slice(0, 30) || fallback;
  return RESERVED_VARIABLES.includes(name) ? `${name}_` : name;
};
