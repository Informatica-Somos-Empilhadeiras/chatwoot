/* global axios */
// OUTSIDER: busca de conversas, contatos e mensagens
// (ver app/controllers/api/v1/accounts/outsider/conversation_searches_controller.rb e message_searches_controller.rb)
import ApiClient from '../ApiClient';

class ConversationSearchAPI extends ApiClient {
  constructor() {
    super('outsider/conversation_searches', { accountScoped: true });
  }

  search(q, signal) {
    return axios.get(this.url, { params: { q }, signal });
  }

  searchMessages(q, beforeId, signal) {
    return axios.get(`${this.baseUrl()}/outsider/message_searches`, {
      params: { q, before_id: beforeId },
      signal,
    });
  }
}

export default new ConversationSearchAPI();
