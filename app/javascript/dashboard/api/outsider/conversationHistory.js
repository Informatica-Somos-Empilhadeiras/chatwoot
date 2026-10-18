/* global axios */
// OUTSIDER: busca dentro da conversa e navegação por data
// (ver app/controllers/api/v1/accounts/outsider/conversation_histories_controller.rb)
import ApiClient from '../ApiClient';

class ConversationHistoryAPI extends ApiClient {
  constructor() {
    super('outsider/conversations', { accountScoped: true });
  }

  search(conversationId, { q, since, until, beforeId }, signal) {
    return axios.get(`${this.url}/${conversationId}/history/search`, {
      params: { q, since, until, before_id: beforeId },
      signal,
    });
  }

  days(conversationId, timeZone) {
    return axios.get(`${this.url}/${conversationId}/history/days`, {
      params: { time_zone: timeZone },
    });
  }

  locate(conversationId, at) {
    return axios.get(`${this.url}/${conversationId}/history/locate`, {
      params: { at },
    });
  }
}

export default new ConversationHistoryAPI();
