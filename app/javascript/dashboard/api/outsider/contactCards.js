/* global axios */
// OUTSIDER: enviar contato pelo WhatsApp (ver app/controllers/api/v1/accounts/outsider/contact_cards_controller.rb)
import ApiClient from '../ApiClient';

class ContactCardsAPI extends ApiClient {
  constructor() {
    super('outsider/contact_cards', { accountScoped: true });
  }

  send(conversationId, contacts) {
    return axios.post(this.url, {
      conversation_id: conversationId,
      contacts,
    });
  }
}

export default new ContactCardsAPI();
