// OUTSIDER: ícone e cor de cada tipo de arquivo na tela de arquivos dos Aplicativos.
const TYPES = [
  [/^(pdf)$/, 'i-lucide-file-text', 'text-n-ruby-10'],
  [/^(docx?|odt|rtf)$/, 'i-lucide-file-text', 'text-n-blue-10'],
  [/^(xlsx?|csv|ods)$/, 'i-lucide-file-spreadsheet', 'text-n-teal-10'],
  [/^(pptx?|odp)$/, 'i-lucide-presentation', 'text-n-amber-10'],
  [/^(png|jpe?g|gif|webp|bmp|heic|svg)$/, 'i-lucide-image', 'text-n-iris-10'],
  [/^(mp4|mov|m4v|webm|avi|mkv|3gp|wmv)$/, 'i-lucide-film', 'text-n-iris-10'],
  [/^(mp3|m4a|ogg|oga|opus|wav|aac|flac)$/, 'i-lucide-music', 'text-n-iris-10'],
  [/^(zip|rar|7z|tar|gz)$/, 'i-lucide-file-archive', 'text-n-slate-11'],
];

// Documentos, Planilhas e Apresentações do Google não têm extensão no nome: vale o tipo
const GOOGLE_TYPES = {
  'application/vnd.google-apps.document': [
    'i-lucide-file-text',
    'text-n-blue-10',
  ],
  'application/vnd.google-apps.spreadsheet': [
    'i-lucide-file-spreadsheet',
    'text-n-teal-10',
  ],
  'application/vnd.google-apps.presentation': [
    'i-lucide-presentation',
    'text-n-amber-10',
  ],
  'application/vnd.google-apps.form': [
    'i-lucide-list-checks',
    'text-n-iris-10',
  ],
  'application/vnd.google-apps.drawing': [
    'i-lucide-pen-tool',
    'text-n-ruby-10',
  ],
};

// Formulários, Sites, Mapas e afins do Google não viram arquivo: só abrem no próprio Google
const GOOGLE_EXPORTABLE = [
  'application/vnd.google-apps.document',
  'application/vnd.google-apps.spreadsheet',
  'application/vnd.google-apps.presentation',
  'application/vnd.google-apps.drawing',
];
export const canDownload = item =>
  !item.folder &&
  (!String(item.mime || '').startsWith('application/vnd.google-apps.') ||
    GOOGLE_EXPORTABLE.includes(item.mime));

export const fileIcon = item => {
  if (item.folder) return { icon: 'i-lucide-folder', tone: 'text-n-amber-10' };
  const google = GOOGLE_TYPES[item.mime];
  if (google) return { icon: google[0], tone: google[1] };
  const ext = String(item.name || '')
    .split('.')
    .pop()
    .toLowerCase();
  const found = TYPES.find(([pattern]) => pattern.test(ext));
  return found
    ? { icon: found[1], tone: found[2] }
    : { icon: 'i-lucide-file', tone: 'text-n-slate-11' };
};
