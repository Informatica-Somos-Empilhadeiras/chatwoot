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

  setStatus(data) {
    return axios.put(`${this.url}/service_orders/status`, data);
  }

  setAttendanceType(data) {
    return axios.put(`${this.url}/service_orders/attendance_type`, data);
  }

  setTechnician(data) {
    return axios.put(`${this.url}/service_orders/technician`, data);
  }

  // listas de apoio (situações, técnicos, tipos de atendimento) para os seletores da edição da OS
  lists() {
    return axios.get(`${this.url}/lists`);
  }

  // busca de produtos do ERP numa unidade, para vincular a um item da proposta
  catalog(company, q) {
    return axios.get(`${this.url}/catalog`, { params: { company, q } });
  }

  // gera no ERP o orçamento de uma proposta do CRM (company opcional quando há mais de uma unidade)
  generateQuote(data) {
    return axios.post(`${this.url}/quotes`, data);
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
