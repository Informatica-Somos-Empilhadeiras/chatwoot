// OUTSIDER: regras do estúdio de modelos de relatório (aba "Modelos de relatório" da seção ERP). A folha da tela imita o
// PDF do servidor (Outsider::Erp::Prints::Pdf): 1 px = 1 pt numa folha A4 de 595 pt, com as mesmas cores, fontes, margens,
// marcadores e o mesmo arranjo das fotos do checklist. O que vale de verdade é o PDF ("Pré-visualizar PDF").

export const PAGE_WIDTH = 595;
export const MARGINS = { s: 24, m: 36, l: 50 };
export const FONT_CSS = {
  helvetica: 'Helvetica, Arial, sans-serif',
  times: '"Times New Roman", Times, serif',
  courier: '"Courier New", Courier, monospace',
};
export const SAMPLE_PHOTOS_URL = '/outsider/erp-prints';
export const MAX_BLOCKS = 80;

// blocos que servem para qualquer relatório; os outros vêm do tipo (checklist na OS, totais no orçamento)
export const GENERIC_TYPES = [
  'header',
  'heading',
  'text',
  'fields',
  'table',
  'long_text',
  'signatures',
  'image',
  'divider',
  'spacer',
  'page_break',
];

export const BLOCK_ICONS = {
  header: 'i-lucide-panel-top',
  heading: 'i-lucide-heading',
  text: 'i-lucide-text',
  fields: 'i-lucide-layout-grid',
  table: 'i-lucide-table',
  long_text: 'i-lucide-align-left',
  signatures: 'i-lucide-signature',
  image: 'i-lucide-image',
  divider: 'i-lucide-minus',
  spacer: 'i-lucide-move-vertical',
  page_break: 'i-lucide-file-plus-2',
  checklist: 'i-lucide-list-checks',
  totals: 'i-lucide-calculator',
};

export const THEME_COLORS = [
  'primary',
  'accent',
  'text',
  'muted',
  'row',
  'box',
  'line',
];

export const randomId = () =>
  `b${Math.random().toString(16).slice(2, 10).padEnd(8, '0')}`;

const clone = value => JSON.parse(JSON.stringify(value));

export const blockSpec = (catalog, type) =>
  (catalog?.blocks || []).find(item => item.type === type);

// bloco novo com os padrões do servidor; grupo/tabela/texto: o primeiro que ainda não está na folha
export const newBlock = (catalog, type, blocks = []) => {
  const spec = blockSpec(catalog, type);
  const block = { ...clone(spec?.defaults || { type }), id: randomId(), type };
  const pick = (option, list) => {
    const used = blocks
      .filter(item => item.type === type)
      .map(item => item[option]);
    const free = list.find(key => !used.includes(key));
    if (free) block[option] = free;
  };
  if (type === 'fields')
    pick(
      'group',
      catalog.groups.map(item => item.key)
    );
  if (type === 'table')
    pick(
      'table',
      catalog.tables.map(item => item.key)
    );
  if (type === 'long_text')
    pick(
      'field',
      catalog.texts.map(item => item.key)
    );
  return block;
};

export const duplicateBlock = block => ({ ...clone(block), id: randomId() });

// ajuste que só faz sentido com outro: o checklist com fotos não tem "respostas em", o sem fotos não tem título das fotos
const HIDDEN_WHEN = {
  checklist: {
    answers: block => block.photos !== 'without',
    grid_columns: block =>
      block.photos !== 'without' || block.answers !== 'grid',
    title_style: block => block.photos === 'without',
    arrangement: block => block.photos === 'without',
    size: block => block.photos === 'without',
    show_count: block => block.photos === 'without',
    numbering: block => block.photos === 'without',
    max: block => block.photos === 'without',
    show_reading: block => block.photos === 'without',
  },
  header: {
    image_id: block => block.logo !== 'upload',
  },
};

export const optionVisible = (block, name) =>
  !HIDDEN_WHEN[block.type]?.[name]?.(block);

// ---------- textos ----------

export const fillPlaceholders = (text, placeholders = {}) =>
  String(text || '').replace(/\{([a-z_]+)\}/g, (match, key) =>
    Object.prototype.hasOwnProperty.call(placeholders, key)
      ? String(placeholders[key] ?? '')
      : match
  );

export const plain = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

// ---------- cores ----------

export const themeColor = (theme, name) =>
  theme?.colors?.[name] || theme?.colors?.text || '#1D2733';

// branco ou o texto escuro sobre um fundo (mesma conta do PDF)
export const contrastColor = (theme, name) => {
  const hex = themeColor(theme, name).replace('#', '');
  const [red, green, blue] = [0, 2, 4].map(start =>
    parseInt(hex.slice(start, start + 2), 16)
  );
  return (red * 299 + green * 587 + blue * 114) / 1000 > 150
    ? themeColor(theme, 'text')
    : '#FFFFFF';
};

// ---------- campos ----------

// [{ key, label, align }] ligados de um grupo/tabela, na ordem do modelo
export const chosenFields = (content, catalog, list) => {
  const entry = [...(catalog?.groups || []), ...(catalog?.tables || [])].find(
    item => item.key === list
  );
  const known = entry ? entry.fields || entry.columns : [];
  const order = content?.fields?.[list] || known.map(f => ({ ...f }));
  return order
    .filter(item => item.on)
    .map(item => known.find(field => field.key === item.key))
    .filter(Boolean);
};

export const listLabel = (catalog, list) =>
  [
    ...(catalog?.groups || []),
    ...(catalog?.tables || []),
    ...(catalog?.texts || []),
  ].find(item => item.key === list)?.label || list;

// ---------- checklist ----------

export const checklistSections = (values, block) => {
  const filters = (block.sections || []).map(plain);
  const list = values?.checklist || [];
  return filters.length
    ? list.filter(section => filters.includes(plain(section.nome)))
    : list;
};

export const readingOf = item => {
  const arrival = item?.chegada || '';
  const departure = item?.saida || '';
  if (!departure || departure === arrival) return arrival;
  if (!arrival) return departure;
  return `Chegada: ${arrival}  ·  Saída: ${departure}`;
};

// automático: 1 grande, 2 lado a lado, 3 em linha, 4 em 2x2, 5 ou mais em 3 colunas
export const columnsFor = (block, count) => {
  if (block.arrangement === 'grid2') return 2;
  if (block.arrangement === 'grid3') return 3;
  if (block.arrangement === 'one') return 1;
  if (count >= 5) return 3;
  if (count === 4) return 2;
  return Math.min(Math.max(count, 1), 3);
};

const PHOTO_HEIGHTS = { s: [80, 120], m: [125, 200], l: [185, 290] };

export const photoHeight = (block, columns, cellWidth) => {
  const heights = PHOTO_HEIGHTS[block.size] || PHOTO_HEIGHTS.m;
  return Math.min(cellWidth * 0.75, columns === 1 ? heights[1] : heights[0]);
};

export const countLabel = (block, photos) => {
  if (!block.show_count || !photos.length) return '';
  return photos.length === 1 ? '1 foto' : `${photos.length} fotos`;
};

// endereço de uma foto do checklist na tela: amostra (arquivo público) ou a foto da OS de verdade (já buscada)
export const photoSource = (photo, loaded = {}) => {
  if (photo?.sample) return `${SAMPLE_PHOTOS_URL}/${photo.sample}`;
  if (photo?.ref) return loaded[photo.ref] || '';
  return '';
};

// ---------- modelo ----------

// a parte do modelo que o estúdio edita e salva
export const editableContent = template => clone(template?.content || {});

export const sameContent = (left, right) =>
  JSON.stringify(left) === JSON.stringify(right);
