/* global axios */
// OUTSIDER: encaminhar mensagem (ver app/controllers/api/v1/accounts/outsider/message_forwards_controller.rb)
import ApiClient from '../ApiClient';

class MessageForwardAPI extends ApiClient {
  constructor() {
    super('outsider/message_forwards', { accountScoped: true });
  }

  forward({ contactId, inboxId, sourceId, content, attachmentIds }) {
    return axios.post(this.url, {
      contact_id: contactId,
      inbox_id: inboxId,
      source_id: sourceId,
      content,
      attachment_ids: attachmentIds,
    });
  }
}

export default new MessageForwardAPI();
