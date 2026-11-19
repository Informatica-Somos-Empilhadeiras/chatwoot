/* global axios */
// OUTSIDER: integração com o ERP Mais Prático (app/controllers/api/v1/accounts/outsider/erp/)
import ApiClient from '../ApiClient';

class ErpAPI extends ApiClient {
  constructor() {
    super('outsider/erp', { accountScoped: true });
  }

  status() {
    return axios.get(`${this.url}/status`);
  }

  settings() {
    return axios.get(`${this.url}/settings`);
  }

  saveSettings(settings) {
    return axios.patch(`${this.url}/settings`, { settings });
  }

  test() {
    return axios.post(`${this.url}/settings/test`);
  }

  contactOrders(contactId) {
    return axios.get(`${this.url}/service_orders`, {
      params: { contact_id: contactId },
    });
  }

  search(q) {
    return axios.get(`${this.url}/service_orders`, { params: { q } });
  }

  board(params) {
    return axios.get(`${this.url}/service_orders/board`, { params });
  }

  setSubstatus(data) {
    return axios.put(`${this.url}/service_orders/substatus`, data);
  }

  setField(data) {
    return axios.put(`${this.url}/service_orders/field`, data);
  }

  customers(q) {
    return axios.get(`${this.url}/customers`, { params: { q } });
  }

  link(data) {
    return axios.post(`${this.url}/contact_link`, data);
  }

  unlink(data) {
    return axios.delete(`${this.url}/contact_link`, { data });
  }

  quotes(contactId) {
    return axios.get(`${this.url}/quotes`, {
      params: { contact_id: contactId },
    });
  }
}

export default new ErpAPI();
