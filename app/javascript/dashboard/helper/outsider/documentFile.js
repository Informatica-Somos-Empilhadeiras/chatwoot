// OUTSIDER: documentos das conversas (PDF, Word, Excel, PowerPoint, texto): cor e sigla do ícone, nome, e se
// dá para visualizar dentro do Chatwoot (components-next/outsider/fileViewer). Aceita anexo em camelCase (balão)
// ou snake_case (painel do contato).
const WORD = ['doc', 'docx', 'docm', 'dotx', 'dotm'];
const EXCEL = ['xls', 'xlsx', 'xlsm', 'xlsb'];
const POWERPOINT = ['ppt', 'pptx', 'pptm', 'pps', 'ppsx', 'potx'];
const TEXT = ['txt', 'csv', 'tsv', 'log', 'json', 'xml', 'md'];
const ARCHIVE = ['zip', 'rar', '7z', 'gz', 'tar'];

export const VIEWABLE_EXTENSIONS = [
  'pdf',
  ...WORD,
  ...EXCEL,
  ...POWERPOINT,
  ...TEXT,
];

export const docColor = extension => {
  const ext = String(extension || '').toLowerCase();
  if (ext === 'pdf') return '#E5484D';
  if (WORD.includes(ext)) return '#2B579A';
  if (EXCEL.includes(ext)) return '#217346';
  if (POWERPOINT.includes(ext)) return '#D24726';
  if (TEXT.includes(ext)) return '#64748B';
  if (ARCHIVE.includes(ext)) return '#8B5CF6';
  return '#6B7280';
};

const urlOf = attachment => attachment?.dataUrl || attachment?.data_url || '';

export const fileNameOf = attachment => {
  if (attachment?.name) return attachment.name;
  const last = urlOf(attachment).split('?')[0].split('/').pop() || '';
  try {
    return decodeURIComponent(last);
  } catch (error) {
    return last;
  }
};

export const extensionOf = attachment => {
  const given = attachment?.extension;
  if (given) return String(given).toLowerCase();
  const name = fileNameOf(attachment);
  return name.includes('.') ? name.split('.').pop().toLowerCase() : '';
};

export const canViewInChatwoot = extension =>
  VIEWABLE_EXTENSIONS.includes(String(extension || '').toLowerCase());

// um documento sozinho na mensagem (com ou sem legenda), fora das caixas de e-mail
export const isDocumentMessage = props =>
  !props.isEmailInbox &&
  Array.isArray(props.attachments) &&
  props.attachments.length === 1 &&
  props.attachments[0].fileType === 'file' &&
  !!urlOf(props.attachments[0]);
