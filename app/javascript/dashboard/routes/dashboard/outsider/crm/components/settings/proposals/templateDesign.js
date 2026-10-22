// OUTSIDER: desenho do modelo de proposta no editor (Entrega 16): blocos do conteúdo e papel timbrado.
// Os limites e os padrões seguem app/services/outsider/crm/proposal_template_layout.rb, que limpa o que
// chega do navegador; aqui eles só evitam mandar valor que o servidor ia trocar.

export const FONTS = [
  { value: 'Helvetica', css: 'Helvetica, Arial, sans-serif' },
  { value: 'Times-Roman', css: '"Times New Roman", Times, serif' },
  { value: 'Courier', css: '"Courier New", Courier, monospace' },
];

export const PAGE_WIDTH_MM = 210;
export const PAGE_HEIGHT_MM = 297;
export const PT_TO_MM = 25.4 / 72;
export const MAX_BLOCKS = 40;
export const MAX_ELEMENTS = 20;
export const BLOCK_SIZES = { min: 6, max: 16 };
export const ELEMENT_SIZES = { min: 6, max: 40 };
export const MARGIN_RANGE = { min: 0, max: 80 };
export const DEFAULT_MARGINS = { side: 12.7, top: 6.4, bottom: 7.8 };

// textos do modelo que cada bloco edita (chaves de sempre do content) e o ícone da lista
export const BLOCK_INFO = {
  date_number: { icon: 'i-lucide-calendar', texts: [] },
  customer: { icon: 'i-lucide-building-2', texts: [] },
  intro: { icon: 'i-lucide-align-left', texts: ['intro'] },
  title: { icon: 'i-lucide-heading', texts: ['title_prefix'] },
  specs: { icon: 'i-lucide-forklift', texts: [] },
  items: { icon: 'i-lucide-table', texts: ['total_label'] },
  conditions: { icon: 'i-lucide-list-checks', texts: [] },
  parties: {
    icon: 'i-lucide-users',
    texts: ['parties_text', 'acceptance_text'],
  },
  closing: { icon: 'i-lucide-message-square-text', texts: ['closing'] },
  bank: {
    icon: 'i-lucide-landmark',
    texts: ['order_heading', 'bank_heading', 'documents_heading'],
  },
  signature: { icon: 'i-lucide-pen-line', texts: ['signature_box'] },
  notes: { icon: 'i-lucide-sticky-note', texts: [] },
  text: { icon: 'i-lucide-type', texts: [] },
};

// blocos que ligavam pelas chaves antigas do modelo; ao salvar os blocos, as chaves acompanham
export const FLAG_OF_BLOCK = {
  specs: 'show_specs',
  parties: 'show_parties',
  bank: 'show_bank',
};

let nextId = 0;
const uid = prefix => {
  nextId += 1;
  return `${prefix}-${Date.now().toString(36)}-${nextId}`;
};

export const textBlock = () => ({
  key: uid('text'),
  type: 'text',
  visible: true,
  new_page: false,
  size: 9,
  bold: false,
  highlight: false,
  heading: '',
  text: '',
});

// medidas em mm a partir do canto de cima à esquerda da folha A4
export const newElement = (type, extra = {}) => ({
  id: uid('el'),
  type,
  x: 20,
  y: 20,
  width: type === 'image' ? 40 : 80,
  pages: 'all',
  text: '',
  size: 10,
  bold: false,
  highlight: false,
  color: '000000',
  align: 'left',
  image_id: null,
  ...extra,
});

export const clamp = (value, min, max) =>
  Math.min(max, Math.max(min, Number(value) || 0));

export const round1 = value => Math.round(Number(value) * 10) / 10;

export const fontCss = font =>
  (FONTS.find(item => item.value === font) || FONTS[0]).css;

// cópia dos blocos e do papel timbrado no formato do formulário
export const blocksOf = content =>
  (content?.blocks || []).map(block => ({ ...block }));

export const layoutOf = content => {
  const layout = content?.layout || {};
  return {
    font: layout.font || FONTS[0].value,
    header_pages: layout.header_pages === 'first' ? 'first' : 'all',
    footer_pages: layout.footer_pages === 'first' ? 'first' : 'all',
    margins: { ...DEFAULT_MARGINS, ...(layout.margins || {}) },
    elements: (layout.elements || []).map(element => ({ ...element })),
  };
};
