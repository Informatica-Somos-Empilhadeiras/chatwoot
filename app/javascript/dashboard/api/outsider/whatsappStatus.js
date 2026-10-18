/* global axios */
// OUTSIDER: página Status do WhatsApp (ver app/controllers/api/v1/accounts/outsider/whatsapp_statuses_controller.rb)
import ApiClient from '../ApiClient';

class WhatsappStatusAPI extends ApiClient {
  constructor() {
    super('outsider/whatsapp_statuses', { accountScoped: true });
  }

  getInboxes() {
    return axios.get(`${this.url}/inboxes`);
  }

  getContacts(inboxId) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  getMine(inboxId, period) {
    return axios.get(`${this.url}/mine`, {
      params: { inbox_id: inboxId, period },
    });
  }

  getMedia(inboxId, id) {
    return axios.get(`${this.url}/media`, {
      params: { inbox_id: inboxId, id },
      responseType: 'blob',
    });
  }

  getAudience(inboxId) {
    return axios.get(`${this.url}/audience`, {
      params: { inbox_id: inboxId },
    });
  }

  publish(formData) {
    return axios.post(this.url, formData);
  }

  republish(payload) {
    return axios.post(`${this.url}/republish`, payload);
  }

  getPermissions() {
    return axios.get(`${this.url}/permissions`);
  }

  updatePermission(userId, permission, allowed) {
    return axios.patch(`${this.url}/permissions`, {
      user_id: userId,
      permission,
      allowed,
    });
  }
}

export default new WhatsappStatusAPI();
