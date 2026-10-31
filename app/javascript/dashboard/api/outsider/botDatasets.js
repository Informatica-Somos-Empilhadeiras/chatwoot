/* global axios */
// OUTSIDER: planilhas do bot (ver app/controllers/api/v1/accounts/outsider/bot_datasets_controller.rb)
import ApiClient from '../ApiClient';

class BotDatasetsAPI extends ApiClient {
  constructor() {
    super('outsider/bot_datasets', { accountScoped: true });
  }

  search(id, q) {
    return axios.get(`${this.url}/${id}`, { params: { q } });
  }

  // um pedaço do envio: { generation, offset, columns, rows }
  rows(id, payload) {
    return axios.post(`${this.url}/${id}/rows`, payload);
  }

  finish(id, payload) {
    return axios.post(`${this.url}/${id}/finish`, payload);
  }

  lookup(id, params) {
    return axios.get(`${this.url}/${id}/lookup`, { params });
  }
}

export default new BotDatasetsAPI();
