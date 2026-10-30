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
}

export default new BotFlowsAPI();
