/* global axios */
// OUTSIDER: pedidos de transferência de conversa entre agentes
// (ver app/controllers/api/v1/accounts/outsider/transfer_requests_controller.rb)
import ApiClient from '../ApiClient';

class TransferRequestsAPI extends ApiClient {
  constructor() {
    super('outsider/transfer_requests', { accountScoped: true });
  }

  request(conversationId, note) {
    return axios.post(this.url, { conversation_id: conversationId, note });
  }

  accept(id) {
    return axios.post(`${this.url}/${id}/accept`);
  }

  decline(id, note) {
    return axios.post(`${this.url}/${id}/decline`, { note });
  }

  acknowledge(id) {
    return axios.post(`${this.url}/${id}/acknowledge`);
  }

  cancel(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new TransferRequestsAPI();
