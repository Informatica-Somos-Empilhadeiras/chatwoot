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

  serviceOrdersList(params) {
    return axios.get(`${this.url}/service_orders/list`, { params });
  }

  quotesList(params) {
    return axios.get(`${this.url}/quotes/list`, { params });
  }

  salesOrders(params) {
    return axios.get(`${this.url}/sales_orders`, { params });
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

  // lista de peças e serviços do ERP numa unidade (abre pronta; q filtra por código ou nome)
  catalog(company, q) {
    return axios.get(`${this.url}/catalog`, { params: { company, q } });
  }

  // descrição técnica de um produto (aberta só quando pedida)
  technical(company, code) {
    return axios.get(`${this.url}/catalog/technical`, {
      params: { company, code },
    });
  }

  // orçamento de peças e serviços feito no chat (separado da proposta comercial do CRM)
  budgets(contactId) {
    return axios.get(`${this.url}/budgets`, {
      params: { contact_id: contactId },
    });
  }

  budget(id) {
    return axios.get(`${this.url}/budgets/${id}`);
  }

  // rascunho novo: contact_id, conversation_id (número da conversa), opportunity_id
  createBudget(data) {
    return axios.post(`${this.url}/budgets`, data);
  }

  saveBudget(id, budget) {
    return axios.patch(`${this.url}/budgets/${id}`, { budget });
  }

  deleteBudget(id) {
    return axios.delete(`${this.url}/budgets/${id}`);
  }

  submitBudget(id) {
    return axios.post(`${this.url}/budgets/${id}/submit`);
  }

  copyBudget(id, data) {
    return axios.post(`${this.url}/budgets/${id}/copy`, data);
  }

  // orçamento feito no próprio Mais Prático: vira registro para PDF, envio e cópia
  importBudget(data) {
    return axios.post(`${this.url}/budgets/import`, data);
  }

  // PDF montado na hora (prévia do rascunho ou o oficial do ERP), como arquivo
  budgetPdf(id) {
    return axios.get(`${this.url}/budgets/${id}/pdf`, { responseType: 'blob' });
  }

  budgetDelivery(id) {
    return axios.get(`${this.url}/budgets/${id}/delivery`);
  }

  budgetContacts(id, q) {
    return axios.get(`${this.url}/budgets/${id}/contacts`, { params: { q } });
  }

  deliverBudget(id, data) {
    return axios.post(`${this.url}/budgets/${id}/deliver`, data);
  }

  // desconto acima do limite: código e senha de quem libera no ERP (a senha não fica guardada em lugar nenhum)
  approveDiscount(id, data) {
    return axios.post(`${this.url}/budgets/${id}/approve_discount`, data);
  }

  // listas do formulário: formas de pagamento, vendedores, gêneros e fretes
  budgetOptions(company) {
    return axios.get(`${this.url}/budgets/options`, { params: { company } });
  }

  // clientes do ERP para vincular: sem q e com o contato, os parecidos com ele vêm primeiro
  customers(q, contactId) {
    return axios.get(`${this.url}/customers`, {
      params: { q, contact_id: contactId || undefined },
    });
  }

  // formas de pagamento do ERP (Configurações > Criar orçamento)
  paymentTerms() {
    return axios.get(`${this.url}/settings/payment_terms`);
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
