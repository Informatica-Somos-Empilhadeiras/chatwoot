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

  // colegas com ramal e quem está conectado (Entrega 23)
  team() {
    return axios.get(`${this.url}/voice/team`);
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

  // painel (wallboard) da Telefonia: period = today | yesterday | week | last_week | month | last_month |
  // custom (com from e to)
  getWallboard(params) {
    return axios.get(`${this.url}/crm/calls/wallboard`, { params });
  }

  // Entrega 24: kind = pdf | calls | agents | days; source = history (lista de Ligações com os filtros)
  exportCalls(params) {
    return axios.get(`${this.url}/crm/calls/export`, {
      params,
      responseType: 'blob',
    });
  }

  // gravação feita pelo telefone, enviada no fim da ligação (Entrega 24)
  // parties: quem estava na ligação, [{ number, started_at }], o cliente primeiro
  uploadRecording(blob, parties) {
    const form = new FormData();
    const extension = blob.type.includes('ogg') ? 'ogg' : 'webm';
    form.append('file', blob, `ligacao.${extension}`);
    form.append('parties', JSON.stringify(parties));
    return axios.post(`${this.url}/voice/recording`, form);
  }

  deleteRecording(callId) {
    return axios.delete(`${this.url}/crm/calls/${callId}/recording`);
  }
}

export default new VoiceAPI();
