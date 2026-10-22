/* global axios */
// OUTSIDER: enviar localização pelo WhatsApp (ver app/controllers/api/v1/accounts/outsider/locations_controller.rb)
import ApiClient from '../ApiClient';

class LocationsAPI extends ApiClient {
  constructor() {
    super('outsider/locations', { accountScoped: true });
  }

  search(query, options = {}) {
    return axios.get(`${this.url}/search`, {
      params: { q: query },
      ...options,
    });
  }

  saved() {
    return axios.get(`${this.url}/saved`);
  }

  save(location) {
    return axios.post(`${this.url}/saved`, { location });
  }

  remove(id) {
    return axios.delete(`${this.url}/saved/${id}`);
  }

  send(conversationId, location) {
    return axios.post(this.url, { conversation_id: conversationId, location });
  }
}

export default new LocationsAPI();
