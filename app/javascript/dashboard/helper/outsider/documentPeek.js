// OUTSIDER: o começo do documento para a miniatura do cartão (estilo WhatsApp). Word, Excel, PowerPoint e texto vêm
// do servidor (Outsider::FilePeek); no PDF o servidor só dá o endereço e o navegador desenha a primeira página.
// Uma vez por anexo enquanto o Chatwoot estiver aberto.
import FileViewsAPI from 'dashboard/api/outsider/fileViews';
import { pdfThumb } from './pdfThumb';

export const PEEKABLE_EXTENSIONS = [
  'pdf',
  'docx',
  'docm',
  'dotx',
  'dotm',
  'xlsx',
  'xlsm',
  'pptx',
  'pptm',
  'ppsx',
  'potx',
  'txt',
  'csv',
  'tsv',
  'log',
  'json',
  'xml',
  'md',
];

const cache = new Map();

export const canPeek = extension =>
  PEEKABLE_EXTENSIONS.includes(String(extension || '').toLowerCase());

const pdfUrl = async attachmentId => {
  const { data } = await FileViewsAPI.peek(attachmentId);
  if (data.type !== 'pdf' || !data.url) throw new Error('no_preview');
  return data.url;
};

export const documentPeek = (attachmentId, extension) => {
  if (cache.has(attachmentId)) return cache.get(attachmentId);
  const job =
    extension === 'pdf'
      ? pdfThumb(`a${attachmentId}`, () => pdfUrl(attachmentId)).then(
          thumb => ({ type: 'image', src: thumb.src, pages: thumb.pages })
        )
      : FileViewsAPI.peek(attachmentId).then(({ data }) => data);
  cache.set(attachmentId, job);
  job.catch(() => cache.delete(attachmentId));
  return job;
};
