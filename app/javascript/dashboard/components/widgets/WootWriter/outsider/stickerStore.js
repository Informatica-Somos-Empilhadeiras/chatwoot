// OUTSIDER: a coleção de figurinhas do atendente na memória da página (carregada uma vez por conta),
// compartilhada pelo seletor da caixa de resposta (StickerPicker.vue) e pelo "Salvar" do balão
// (components-next/message/outsider/StickerBubble.vue).
import { reactive } from 'vue';
import StickersAPI from 'dashboard/api/outsider/stickers';

export const stickerState = reactive({
  accountId: null,
  loaded: false,
  loading: false,
  error: false,
  stickers: [],
  packs: [],
  limits: { stickers: 1000, packs: 40 },
  savedAttachmentIds: [], // anexos desta sessão já guardados pelo botão "Salvar" do balão
});

let request = 0;

export const loadStickers = async (accountId, force = false) => {
  if (!accountId) return;
  const same = stickerState.accountId === accountId;
  if (same && !force && (stickerState.loaded || stickerState.loading)) return;
  request += 1;
  const current = request;
  stickerState.accountId = accountId;
  stickerState.loading = true;
  stickerState.error = false;
  if (!same) {
    stickerState.loaded = false;
    stickerState.stickers = [];
    stickerState.packs = [];
  }
  try {
    const { data } = await StickersAPI.list();
    if (current !== request) return;
    stickerState.stickers = data.stickers || [];
    stickerState.packs = data.packs || [];
    stickerState.limits = data.limits || stickerState.limits;
    stickerState.loaded = true;
  } catch (error) {
    if (current === request) stickerState.error = true;
  } finally {
    if (current === request) stickerState.loading = false;
  }
};

export const putSticker = sticker => {
  const index = stickerState.stickers.findIndex(s => s.id === sticker.id);
  if (index >= 0) stickerState.stickers.splice(index, 1, sticker);
  else stickerState.stickers.push(sticker);
};

export const dropSticker = id => {
  stickerState.stickers = stickerState.stickers.filter(s => s.id !== id);
};

export const markUsed = id => {
  const sticker = stickerState.stickers.find(s => s.id === id);
  if (!sticker) return;
  sticker.last_used_at = new Date().toISOString();
  sticker.uses_count = (sticker.uses_count || 0) + 1;
};

export const putPack = pack => {
  const index = stickerState.packs.findIndex(p => p.id === pack.id);
  if (index >= 0) stickerState.packs.splice(index, 1, pack);
  else stickerState.packs.push(pack);
};

export const dropPack = id => {
  stickerState.packs = stickerState.packs.filter(p => p.id !== id);
  stickerState.stickers.forEach(sticker => {
    if (sticker.pack_id === id) sticker.pack_id = null;
  });
};

// figurinha (ou foto) recebida numa conversa vai para a coleção; devolve { sticker, existed }
export const saveAttachmentAsSticker = async attachmentId => {
  const { data } = await StickersAPI.createFromAttachment(attachmentId);
  if (data?.sticker) putSticker(data.sticker);
  if (!stickerState.savedAttachmentIds.includes(attachmentId)) {
    stickerState.savedAttachmentIds.push(attachmentId);
  }
  return data;
};

// mensagem de erro do servidor ("file_type", "too_many"...) traduzida, ou o texto padrão
export const stickerErrorText = (t, error, fallbackKey) => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_WHATSAPP.STICKERS.ERRORS.${code}`;
  if (code && t(key) !== key) return t(key);
  return t(`OUTSIDER_WHATSAPP.STICKERS.${fallbackKey}`);
};
