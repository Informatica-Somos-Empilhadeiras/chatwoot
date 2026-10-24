/* global axios */
// OUTSIDER: reagir e editar mensagem do WhatsApp (ver app/controllers/api/v1/accounts/outsider/whatsapp_messages_controller.rb)
import ApiClient from '../ApiClient';

class WhatsappMessagesAPI extends ApiClient {
  constructor() {
    super('outsider/whatsapp_messages', { accountScoped: true });
  }

  edit(messageId, content) {
    return axios.patch(`${this.url}/${messageId}`, { content });
  }

  // emoji vazio tira a reação
  react(messageId, emoji) {
    return axios.post(`${this.url}/${messageId}/reaction`, { emoji });
  }
}

export default new WhatsappMessagesAPI();
