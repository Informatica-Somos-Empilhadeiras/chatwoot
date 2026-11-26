/* global axios */
// OUTSIDER: Google Maps na agenda: chave do Maps e locais do cliente
// (ver app/controllers/api/v1/accounts/outsider/maps_controller.rb e contact_places_controller.rb)
import ApiClient from '../ApiClient';

class MapsAPI extends ApiClient {
  constructor() {
    super('outsider', { accountScoped: true });
  }

  settings() {
    return axios.get(`${this.url}/maps`);
  }

  places(contactId) {
    return axios.get(`${this.url}/contacts/${contactId}/places`);
  }

  createPlace(contactId, place) {
    return axios.post(`${this.url}/contacts/${contactId}/places`, { place });
  }

  updatePlace(contactId, id, place) {
    return axios.patch(`${this.url}/contacts/${contactId}/places/${id}`, {
      place,
    });
  }

  // Mapa dos agendamentos (Outsider::Erp::ScheduleMap)
  scheduleMap(params) {
    return axios.get(`${this.url}/erp/schedule_map`, { params });
  }

  mapClient(company, code) {
    return axios.get(`${this.url}/erp/schedule_map/client`, {
      params: { company, code },
    });
  }

  completeClient(company, code, values) {
    return axios.post(`${this.url}/erp/schedule_map/complete`, {
      company,
      code,
      values,
    });
  }

  saveSettings(data) {
    return axios.put(`${this.url}/maps`, data);
  }

  removePlace(contactId, id) {
    return axios.delete(`${this.url}/contacts/${contactId}/places/${id}`);
  }
}

export default new MapsAPI();
