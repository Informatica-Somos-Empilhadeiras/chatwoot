/* global axios */
// OUTSIDER: visualizador de documentos (ver app/controllers/api/v1/accounts/outsider/file_views_controller.rb)
import ApiClient from '../ApiClient';

class FileViewsAPI extends ApiClient {
  constructor() {
    super('outsider/file_views', { accountScoped: true });
  }

  // como abrir um anexo: { kind: pdf|office|text|none, reason, view_url, download_url, name, size }
  show(attachmentId) {
    return axios.get(`${this.url}/${attachmentId}`);
  }

  // começo do arquivo para a miniatura: { type: pdf|image|text|table|none, url, src, lines, rows, pages }
  peek(attachmentId) {
    return axios.get(`${this.url}/${attachmentId}/peek`);
  }
}

export default new FileViewsAPI();
