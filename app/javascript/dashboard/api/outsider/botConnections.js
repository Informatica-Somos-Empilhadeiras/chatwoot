/* global axios */
// OUTSIDER: conexões do bot com outros sistemas (ver app/controllers/api/v1/accounts/outsider/bot_connections_controller.rb)
import ApiClient from '../ApiClient';

class BotConnectionsAPI extends ApiClient {
  constructor() {
    super('outsider/bot_connections', { accountScoped: true });
  }

  test(id) {
    return axios.post(`${this.url}/${id}/test`);
  }

  folders(id, path) {
    return axios.get(`${this.url}/${id}/folders`, { params: { path } });
  }

  remove(id, force = false) {
    return axios.delete(`${this.url}/${id}`, { params: { force } });
  }
}

export default new BotConnectionsAPI();
