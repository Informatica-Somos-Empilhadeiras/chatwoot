/* global axios */
// OUTSIDER: aviso novo no navegador e no celular (Configurações > Notificações).
// Ver app/controllers/api/v1/accounts/outsider/push_controller.rb
import ApiClient from '../ApiClient';

class OutsiderPushAPI extends ApiClient {
  constructor() {
    super('outsider', { accountScoped: true });
  }

  get() {
    return axios.get(`${this.url}/push`);
  }

  update(prefs) {
    return axios.patch(`${this.url}/push`, { prefs });
  }

  register(data) {
    return axios.post(`${this.url}/push/devices`, data);
  }

  unregister(deviceId) {
    return axios.delete(`${this.url}/push/devices/${deviceId}`);
  }

  permission(permission) {
    return axios.post(`${this.url}/push/permission`, { permission });
  }

  test() {
    return axios.post(`${this.url}/push/test`);
  }

  remind(userId) {
    return axios.post(`${this.url}/push/remind/${userId}`);
  }
}

export default new OutsiderPushAPI();
