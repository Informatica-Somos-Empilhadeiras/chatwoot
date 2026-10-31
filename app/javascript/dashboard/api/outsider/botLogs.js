/* global axios */
// OUTSIDER: registro das chamadas do bot (ver app/controllers/api/v1/accounts/outsider/bot_logs_controller.rb)
import ApiClient from '../ApiClient';

class BotLogsAPI extends ApiClient {
  constructor() {
    super('outsider/bot_logs', { accountScoped: true });
  }

  list(params) {
    return axios.get(this.url, { params });
  }
}

export default new BotLogsAPI();
