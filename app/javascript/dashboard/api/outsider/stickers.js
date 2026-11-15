/* global axios */
// OUTSIDER: figurinhas do WhatsApp, coleção do atendente e envio
// (ver app/controllers/api/v1/accounts/outsider/stickers_controller.rb)
import ApiClient from '../ApiClient';

class StickersAPI extends ApiClient {
  constructor() {
    super('outsider/stickers', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  upload(file) {
    const form = new FormData();
    form.append('file', file, file.name || 'figurinha');
    return axios.post(this.url, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  createFromAttachment(attachmentId) {
    return axios.post(this.url, { attachment_id: attachmentId });
  }

  update(id, attributes) {
    return axios.patch(`${this.url}/${id}`, attributes);
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  send(id, conversationId) {
    return axios.post(`${this.url}/${id}/send`, {
      conversation_id: conversationId,
    });
  }

  get packsUrl() {
    return this.url.replace(/stickers$/, 'sticker_packs');
  }

  createPack(name) {
    return axios.post(this.packsUrl, { name });
  }

  updatePack(id, attributes) {
    return axios.patch(`${this.packsUrl}/${id}`, attributes);
  }

  removePack(id) {
    return axios.delete(`${this.packsUrl}/${id}`);
  }
}

export default new StickersAPI();
