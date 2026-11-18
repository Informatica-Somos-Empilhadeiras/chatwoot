/* global axios */
// OUTSIDER: perfis de acesso por tela (Configurações > Perfis de acesso) e o acesso de quem está logado
import ApiClient from '../ApiClient';

class AccessAPI extends ApiClient {
  constructor() {
    super('outsider', { accountScoped: true });
  }

  me() {
    return axios.get(`${this.url}/access`);
  }

  profiles() {
    return axios.get(`${this.url}/access_profiles`);
  }

  createProfile(data) {
    return axios.post(`${this.url}/access_profiles`, data);
  }

  updateProfile(id, data) {
    return axios.patch(`${this.url}/access_profiles/${id}`, data);
  }

  deleteProfile(id) {
    return axios.delete(`${this.url}/access_profiles/${id}`);
  }

  people() {
    return axios.get(`${this.url}/access_people`);
  }

  createPerson(data) {
    return axios.post(`${this.url}/access_people`, data);
  }

  updatePerson(id, data) {
    return axios.patch(`${this.url}/access_people/${id}`, data);
  }
}

export default new AccessAPI();
