/* global axios */
// OUTSIDER: fluxos do bot (ver app/controllers/api/v1/accounts/outsider/bot_flows_controller.rb)
import ApiClient from '../ApiClient';

class BotFlowsAPI extends ApiClient {
  constructor() {
    super('outsider/bot_flows', { accountScoped: true });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  // Enviar arquivo: guarda o arquivo no fluxo e devolve { blob_id, name, size, content_type, url }
  uploadFile(id, file, onUploadProgress) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}/${id}/files`, form, { onUploadProgress });
  }

  // Testar de um bloco de integração: { node, variables, contact, flow_id, confirm_write }
  runBlock(payload) {
    return axios.post(`${this.url}/run_block`, payload);
  }
}

export default new BotFlowsAPI();
