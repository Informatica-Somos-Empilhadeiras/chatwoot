// OUTSIDER: fotos e vídeos da área Teams no jeito do WhatsApp.
// - mediaOf: as fotos/vídeos de uma mensagem (o que entra no álbum e no visualizador).
// - viewerItems: tudo o que está carregado no chat/canal, no formato do visualizador do WhatsApp
//   (components-next/outsider/mediaViewer/MediaViewer.vue), do mais antigo para o mais novo.
// - albumRuns: mensagens só com fotos/vídeos, da mesma pessoa e em seguida (até 2 minutos), viram um álbum só,
//   como quando alguém manda dezenas de fotos de uma vez.
// - startDownload / downloadZip: Baixar sai pelo Chatwoot (Outsider::TeamsDownloadsController).
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';

export const MEDIA_KINDS = ['image', 'video'];
export const ALBUM_GAP_MS = 2 * 60 * 1000;

export const isMedia = item =>
  MEDIA_KINDS.includes(item?.kind) && !!(item.thumb_url || item.full_url);

export const mediaOf = message => (message?.attachments || []).filter(isMedia);

export const mediaKey = (message, item) => `t-${message.id}-${item.index}`;

export const viewerItem = (message, item, youLabel = 'Você') => ({
  id: mediaKey(message, item),
  message_id: message.id,
  file_type: item.kind,
  data_url:
    item.kind === 'video' ? item.video_url : item.full_url || item.thumb_url,
  thumb_url: item.thumb_url,
  created_at: Math.floor(new Date(message.sent_at).getTime() / 1000),
  sender: {
    name: message.mine ? youLabel : message.sender_name,
    thumbnail: message.sender_photo || '',
  },
  file_name: item.name,
  extension: item.extension,
  download_url: item.download_url,
  index: item.index,
});

export const viewerItems = (messages, youLabel) =>
  (messages || [])
    .filter(message => !message.deleted)
    .flatMap(message =>
      mediaOf(message).map(item => viewerItem(message, item, youLabel))
    )
    .filter(item => item.data_url);

// mensagem que só tem fotos/vídeos (sem texto, citação ou outro arquivo)
export const isMediaOnly = message =>
  !!message &&
  !message.deleted &&
  !message.content &&
  !message.quote &&
  message.status === 'sent' &&
  (message.attachments || []).length > 0 &&
  (message.attachments || []).every(isMedia);

export const joinsAlbum = (previous, message) =>
  isMediaOnly(previous) &&
  isMediaOnly(message) &&
  previous.mine === message.mine &&
  previous.sender_name === message.sender_name &&
  new Date(message.sent_at) - new Date(previous.sent_at) <= ALBUM_GAP_MS;

// numa aba nova: o arquivo baixa e a aba fecha sozinha; se der erro, a aba mostra o motivo e o Chatwoot fica aberto
const clickLink = url => {
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.target = '_blank';
  anchor.rel = 'noopener';
  anchor.style.display = 'none';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
};

export const startDownload = url => {
  if (url) clickLink(url);
};

// o zip só sai depois de pedir o endereço (sem o clique "na hora", o navegador bloquearia uma aba nova): baixa por
// um quadro escondido; o que não deu para baixar vai listado dentro do próprio zip
const frameDownload = url => {
  const frame = document.createElement('iframe');
  frame.style.display = 'none';
  frame.src = url;
  document.body.appendChild(frame);
  setTimeout(() => frame.remove(), 10 * 60 * 1000);
};

// pairs = [{ message_id, index }]; devolve quantos arquivos foram para o zip
export const downloadZip = async (threadId, pairs) => {
  const { data } = await TeamsGraphAPI.zip(threadId, pairs);
  frameDownload(data.url);
  return data.count;
};
