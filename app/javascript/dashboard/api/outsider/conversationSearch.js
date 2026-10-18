/* global axios */
// OUTSIDER: busca de conversas (ver app/controllers/api/v1/accounts/outsider/conversation_searches_controller.rb)
import ApiClient from '../ApiClient';

class ConversationSearchAPI extends ApiClient {
  constructor() {
    super('outsider/conversation_searches', { accountScoped: true });
  }

  search(q) {
    return axios.get(this.url, { params: { q } });
  }
}

export default new ConversationSearchAPI();
