/* global axios */
// OUTSIDER: telefonia (Entrega 22). Telefone do navegador (voice/me, voice/lookup) e as telas do CRM
// (Configurações > Telefonia, metas de ligação, ligações e painel).
import ApiClient from '../ApiClient';

class VoiceAPI extends ApiClient {
  constructor() {
    super('outsider', { accountScoped: true });
  }

  me() {
    return axios.get(`${this.url}/voice/me`);
  }

  lookup(number) {
    return axios.get(`${this.url}/voice/lookup`, { params: { number } });
  }

  getSettings() {
    return axios.get(`${this.url}/crm/voice_settings`);
  }

  updateSettings(settings) {
    return axios.patch(`${this.url}/crm/voice_settings`, { settings });
  }

  getGoals(month) {
    return axios.get(`${this.url}/crm/call_goals`, { params: { month } });
  }

  updateGoals(month, users) {
    return axios.patch(`${this.url}/crm/call_goals`, { month, users });
  }

  getCalls(params) {
    return axios.get(`${this.url}/crm/calls`, { params });
  }

  getStats(month) {
    return axios.get(`${this.url}/crm/calls/stats`, { params: { month } });
  }
}

export default new VoiceAPI();
