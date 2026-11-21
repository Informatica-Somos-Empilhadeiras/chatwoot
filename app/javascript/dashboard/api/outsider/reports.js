/* global axios */
// OUTSIDER: seção Relatórios de gestão (app/controllers/api/v1/accounts/outsider/reports/)
import ApiClient from '../ApiClient';

class ReportsAPI extends ApiClient {
  constructor() {
    super('outsider/reports', { accountScoped: true });
  }

  // desempenho dos técnicos: { from, to, companies[] }
  technicians(params) {
    return axios.get(`${this.url}/technicians`, { params });
  }

  // só administrador: { report_commission_pct, report_goals: { NOME: valor } }
  saveTechniciansSettings(data) {
    return axios.put(`${this.url}/technicians`, data);
  }
}

export default new ReportsAPI();
